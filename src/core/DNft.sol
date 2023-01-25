// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@solmate/src/utils/ReentrancyGuard.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";
import {PermissionMath} from "../libraries/PermissionMath.sol";

contract DNft is ERC721Enumerable, ReentrancyGuard {
  using SafeCast          for uint256;
  using SafeCast          for int256;
  using SignedMath        for int256;
  using FixedPointMathLib for uint256;
  using LibString         for uint256;
  using PermissionMath    for Permission[];
  using PermissionMath    for uint8;

  uint public immutable MAX_SUPPLY;                    // Max supply of DNfts
  uint public immutable MIN_PRICE_CHANGE_BETWEEN_SYNC; // 10    bps or 0.1%
  uint public immutable MIN_TIME_BETWEEN_SYNC;         
  int  public immutable MIN_MINT_DYAD_DEPOSIT;         // 1 DYAD
  uint public constant MIN_COLLATERIZATION_RATIO = 1.50e18; // 15000 bps or 150%

  uint public constant XP_NORM_FACTOR          = 1e16;
  uint public constant XP_MINT_REWARD          = 1_000;
  uint public constant XP_SYNC_REWARD          = 0.0004e18; // 4 bps    or 0.04%
  uint public constant XP_CLAIM_REWARD         = 0.0001e18; // 1 bps    or 0.01%
  uint public constant XP_SNIPE_BURN_REWARD    = 0.0003e18; // 3 bps    or 0.03%
  uint public constant XP_SNIPE_MINT_REWARD    = 0.0002e18; // 2 bps    or 0.02%
  uint public constant XP_LIQUIDATION_REWARD   = 0.0004e18; // 4 bps    or 0.04%
  int  public constant SNIPE_MINT_SHARE_REWARD = 0.60e18;   // 6000 bps or 60%

  int  public lastEthPrice;           // ETH price from the last sync call
  int  public dyadDelta;              // Amount of dyad to mint/burn in this sync cycle
  int  public prevDyadDelta;          // Amount of dyad to mint/burn in the previous sync cycle
  uint public syncedBlock;            // Start of the current sync cycle
  uint public prevSyncedBlock;        // Start of the previous sync cycle
  uint public totalXp;                // Sum of all dNFTs Xp
  uint public maxXp;                  // Max XP over all dNFTs
  uint public timeOfLastSync;

  struct Nft {
    uint xp;         // always inflationary
    int  deposit;    // deposited dyad
    uint withdrawal; // withdrawn dyad
    uint lastOwnershipChange; // block number of the last ownership change
    bool isActive;
  }

  enum Permission { ACTIVATE, DEACTIVATE, EXCHANGE, DEPOSIT, MOVE, WITHDRAW, REDEEM, CLAIM }

  struct PermissionSet {
    address      operator;    
    Permission[] permissions; // permissions given to the operator
  }

  struct NftPermission {
    uint8   permissions; // bitmap of permissions
    uint248 lastUpdated; // block number of last updated
  }

  mapping(uint => Nft)                               public idToNft;
  mapping(uint => mapping(address => NftPermission)) public idToNftPermission; // id => (operator => NftPermission)
  mapping(uint => mapping(uint => bool))             public idToClaimed;       // id => (blockNumber => claimed)
  mapping(uint => uint)                              public idToLastDeposit; // id => (blockNumber)

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  event Minted     (address indexed to, uint indexed id);
  event Deposited  (uint indexed id, uint amount);
  event Redeemed   (address indexed to, uint indexed id, uint amount);
  event Withdrawn  (uint indexed from, address indexed to, uint amount);
  event Exchanged  (uint indexed id, int amount);
  event Moved      (uint indexed from, uint indexed to, int amount);
  event Synced     (uint id);
  event Claimed    (uint indexed id, int share);
  event Sniped     (uint indexed from, uint indexed to, int share);
  event Activated  (uint id);
  event Deactivated(uint id);
  event Liquidated (address indexed to, uint indexed id);
  event Modified   (uint256 tokenId, PermissionSet[] permissions);

  error ReachedMaxSupply               ();
  error SyncTooSoon                    ();
  error DyadTotalSupplyZero            ();
  error DNftDoesNotExist               (uint id);
  error NotNFTOwner                    (uint id);
  error NotLiquidatable                (uint id);
  error WithdrawalsNotZero             (uint id);
  error DepositIsNegative              (uint id);
  error IsActive                       (uint id);
  error IsInactive                     (uint id);
  error ExceedsAverageTVL              (uint averageTVL);
  error PriceChangeTooSmall            (int priceChange);
  error NotEnoughToCoverDepositMinimum (int amount);
  error NotEnoughToCoverNegativeDeposit(int amount);
  error CrTooLow                       (uint cr);
  error ExceedsDepositBalance          (int deposit);
  error ExceedsWithdrawalBalance       (uint amount);
  error FailedEthTransfer              (address to, uint amount);
  error AlreadyClaimed                 (uint id, uint syncedBlock);
  error AlreadySniped                  (uint id, uint syncedBlock);
  error MissingPermission              (uint id, Permission permission);
  error CannotDepositAndWithdrawInSameBlock(uint blockNumber);

  modifier exists(uint id) {
    if (!_exists(id)) revert DNftDoesNotExist(id); _; 
  }
  modifier onlyOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotNFTOwner(id); _;
  }
  modifier withPermission(uint id, Permission permission) {
    if (!hasPermission(id, msg.sender, permission)) revert MissingPermission(id, permission); _;
  }
  modifier isActive(uint id) {
    if (idToNft[id].isActive == false) revert IsInactive(id); _;
  }
  modifier isInactive(uint id) {
    if (idToNft[id].isActive == true) revert IsActive(id); _;
  }

  constructor(
      address _dyad,
      address _oracle, 
      uint    _maxSupply,
      uint    _minPriceChangeBetweenSync,
      uint    _minTimeBetweenSync,
      int     _minMintDyadDeposit, 
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad                          = Dyad(_dyad);
      oracle                        = IAggregatorV3(_oracle);
      MAX_SUPPLY                    = _maxSupply;
      MIN_PRICE_CHANGE_BETWEEN_SYNC = _minPriceChangeBetweenSync;
      MIN_TIME_BETWEEN_SYNC         = _minTimeBetweenSync;
      MIN_MINT_DYAD_DEPOSIT         = _minMintDyadDeposit;
      lastEthPrice                  = _getLatestEthPrice();

      for (uint i = 0; i < _insiders.length; i++) {
        (uint id, Nft memory nft) = _mintNft(_insiders[i]); // insider DNfts do not require a deposit
        idToNft[id] = nft; 
      }
  }

  // Mint new DNft to `to` 
  function mint(address to) external payable returns (uint) {
      int newDyad  = _eth2dyad(msg.value);
      if (newDyad < MIN_MINT_DYAD_DEPOSIT) { revert NotEnoughToCoverDepositMinimum(newDyad); }
      (uint id, Nft memory nft) = _mintNft(to); 
      nft.deposit  = newDyad;
      nft.isActive = true;
      idToNft[id]  = nft;
      return id;
  }

  // Mint new DNft to `to`
  function _mintNft(address to) private returns (uint, Nft memory) {
      uint id = totalSupply();
      if (id >= MAX_SUPPLY) { revert ReachedMaxSupply(); }
      _mint(to, id); // will revert on address(0)
      Nft memory nft; 
      _addXp(nft, XP_MINT_REWARD);
      emit Minted(to, id);
      return (id, nft);
  }

  // Exchange ETH for DYAD deposit
  function exchange(uint id) external withPermission(id, Permission.EXCHANGE) isActive(id) payable returns (int) {
      idToLastDeposit[id]  = block.number;
      int newDeposit       = _eth2dyad(msg.value);
      idToNft[id].deposit += newDeposit;
      emit Exchanged(id, newDeposit);
      return newDeposit;
  }

  // Deposit DYAD 
  function deposit(
      uint id,
      uint amount
  ) external withPermission(id, Permission.DEPOSIT) isActive(id) { 
      Nft storage nft = idToNft[id];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      idToLastDeposit[id] = block.number;
      dyad.burn(msg.sender, amount);
      unchecked {
      nft.withdrawal -= amount; } // amount <= nft.withdrawal
      nft.deposit    += amount.toInt256();
      emit Deposited(id, amount);
  }

  // Move `amount` `from` one dNFT deposit `to` another dNFT deposit
  function move(
      uint _from,
      uint _to,
      int  _amount
  ) external withPermission(_from, Permission.MOVE) {
      require(_amount > 0);              // needed because _amount is int
      Nft storage from = idToNft[_from];
      if (_amount > from.deposit) { revert ExceedsDepositBalance(from.deposit); }
      unchecked {
      from.deposit         -= _amount; } // amount <= from.deposit
      idToNft[_to].deposit += _amount;
      emit Moved(_from, _to, _amount);
  }

  // Withdraw DYAD from dNFT deposit
  function withdraw(
      uint from,
      address to, 
      uint amount 
  ) external withPermission(from, Permission.WITHDRAW) isActive(from) {
      if (idToLastDeposit[from] == block.number) { 
        revert CannotDepositAndWithdrawInSameBlock(block.number); } // stops flash loan attacks
      Nft storage nft = idToNft[from];
      if (amount.toInt256() > nft.deposit) { revert ExceedsDepositBalance(nft.deposit); }
      uint collatVault    = address(this).balance/1e8 * _getLatestEthPrice().toUint256();
      uint newCollatRatio = collatVault.divWadDown(dyad.totalSupply() + amount);
      if (newCollatRatio < MIN_COLLATERIZATION_RATIO) { revert CrTooLow(newCollatRatio); }
      uint averageTVL    = collatVault / totalSupply();
      uint newWithdrawal = nft.withdrawal + amount;
      if (newWithdrawal > averageTVL) { revert ExceedsAverageTVL(averageTVL); }
      unchecked {
      nft.deposit    -= amount.toInt256(); } // amount <= nft.deposit
      nft.withdrawal  = newWithdrawal; 
      dyad.mint(to, amount);
      emit Withdrawn(from, to, amount);
  }

  // Redeem DYAD for ETH
  function redeem(
      uint from,
      address to,
      uint amount
  ) external nonReentrant withPermission(from, Permission.REDEEM) isActive(from) returns (uint) { 
      Nft storage nft = idToNft[from];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      unchecked {
      nft.withdrawal -= amount; } // amount <= nft.withdrawal
      dyad.burn(msg.sender, amount);
      uint eth = amount*1e8 / _getLatestEthPrice().toUint256();
      (bool success,) = payable(to).call{value: eth}(""); // re-entrancy vector
      if (!success) { revert FailedEthTransfer(msg.sender, eth); }
      emit Redeemed(msg.sender, from, amount);
      return eth;
  }

  // Determine amount of dyad to mint/burn in the next claim window
  function sync(uint id) external isActive(id) returns (int) {
      uint dyadTotalSupply = dyad.totalSupply(); // amount to burn/mint is based only on withdrawn dyad
      if (dyadTotalSupply == 0) { revert DyadTotalSupplyZero(); } 
      if (block.timestamp < timeOfLastSync + MIN_TIME_BETWEEN_SYNC) { revert SyncTooSoon(); }
      int  newEthPrice    = _getLatestEthPrice();
      int  priceChange    = wadDiv(newEthPrice - lastEthPrice, lastEthPrice); 
      uint priceChangeAbs = priceChange.abs();
      if (priceChangeAbs < MIN_PRICE_CHANGE_BETWEEN_SYNC) { revert PriceChangeTooSmall(priceChange); }
      timeOfLastSync   = block.timestamp;
      lastEthPrice     = newEthPrice; 
      prevSyncedBlock  = syncedBlock;  // open new snipe window
      syncedBlock      = block.number; // open new claim window
      prevDyadDelta    = dyadDelta;
      dyadDelta        = wadMul(dyadTotalSupply.toInt256(), priceChange);
      Nft memory nft   = idToNft[id];
      _addXp(nft, _calcXpReward(XP_SYNC_REWARD + priceChangeAbs));
      idToNft[id]      = nft;
      emit Synced(id);
      return dyadDelta;
  }

  // Claim DYAD from the current sync window
  function claim(uint id) external withPermission(id, Permission.CLAIM) isActive(id) returns (int) {
      if (idToClaimed[id][syncedBlock]) { revert AlreadyClaimed(id, syncedBlock); }
      idToClaimed[id][syncedBlock] = true;
      Nft memory nft = idToNft[id];
      int  share;
      uint newXp = _calcXpReward(XP_CLAIM_REWARD);
      if (dyadDelta > 0) {
        share = _calcNftMint(dyadDelta, nft.xp);
      } else {
        uint xp;
        (share, xp) = _calcNftBurn(dyadDelta, nft.xp);
        newXp += xp;
      }
      nft.deposit += share;
      _addXp(nft, newXp);
      idToNft[id] = nft;
      emit Claimed(id, share);
      return share;
  }

  // Snipe DYAD from previouse sync window to get a bonus
  function snipe(
      uint _from,
      uint _to
  ) external isActive(_from) isActive(_to) returns (int) {
      if (idToClaimed[_from][prevSyncedBlock]) { revert AlreadySniped(_from, prevSyncedBlock); }
      idToClaimed[_from][prevSyncedBlock] = true;
      Nft memory from = idToNft[_from];
      Nft memory to   = idToNft[_to];
      int share;
      if (prevDyadDelta > 0) {         
        share         = _calcNftMint(prevDyadDelta, from.xp);
        from.deposit += wadMul(share, 1e18 - SNIPE_MINT_SHARE_REWARD); 
        to.deposit   += wadMul(share, SNIPE_MINT_SHARE_REWARD); 
        _addXp(to, _calcXpReward(XP_SNIPE_MINT_REWARD));
      } else {                        
        uint xp;  
        (share, xp) = _calcNftBurn(prevDyadDelta, from.xp);
        from.deposit += share;      
        _addXp(from, xp);
        _addXp(to, _calcXpReward(XP_SNIPE_BURN_REWARD));
      }
      idToNft[_from] = from;
      idToNft[_to]   = to;
      emit Sniped(_from, _to, share);
      return share;
  }

  // Liquidate DNft by covering its deposit
  function liquidate(
      uint id, 
      address to 
  ) external payable {
      Nft memory nft = idToNft[id];
      int _deposit   = nft.deposit; // save gas
      if (_deposit >= 0) { revert NotLiquidatable(id); }
      int newDyad = _eth2dyad(msg.value);
      if (newDyad < _deposit*-1) { revert NotEnoughToCoverNegativeDeposit(newDyad); }
      _addXp(nft, _calcXpReward(XP_LIQUIDATION_REWARD));
      nft.deposit += newDyad; 
      idToNft[id]  = nft;     
      _transfer(ownerOf(id), to, id);
      emit Liquidated(to,  id); 
  }

  // Activate inactive dNFT
  function activate(uint id) external withPermission(id, Permission.ACTIVATE) isInactive(id) {
    idToNft[id].isActive = true;
    emit Activated(id);
  }

  // Deactivate active dNFT
  function deactivate(uint id) external withPermission(id, Permission.DEACTIVATE) isActive(id) {
    if (idToNft[id].withdrawal  > 0) revert WithdrawalsNotZero(id);
    if (idToNft[id].deposit    <= 0) revert DepositIsNegative(id);
    idToNft[id].isActive = false;
    emit Deactivated(id);
  }

  // Grant and revoke permissions
  function grant(
      uint256 _id,
      PermissionSet[] calldata _permissionSets
  ) external onlyOwner(_id) {
      uint248 _blockNumber = uint248(block.number);
      for (uint256 i = 0; i < _permissionSets.length; ) {
        PermissionSet memory _permissionSet = _permissionSets[i];
        if (_permissionSet.permissions.length == 0) {
          delete idToNftPermission[_id][_permissionSet.operator];
        } else {
          idToNftPermission[_id][_permissionSet.operator] = NftPermission({
            permissions: _permissionSet.permissions._toUInt8(),
            lastUpdated: _blockNumber
          });
        }
        unchecked { i++; }
      }
      emit Modified(_id, _permissionSets);
  }

  function hasPermission(
      uint256 id,
      address operator,
      Permission permission
  ) public view returns (bool) {
      if (ownerOf(id) == operator) { return true; }
      NftPermission memory _nftPermission = idToNftPermission[id][operator];
      return _nftPermission.permissions._hasPermission(permission) &&
        // If there was an ownership change after the permission was last updated,
        // then the operator doesn't have the permission
        idToNft[id].lastOwnershipChange < _nftPermission.lastUpdated;
  }

  function hasPermissions(
      uint256 id,
      address operator,
      Permission[] calldata permissions
  ) external view returns (bool[] memory _hasPermissions) {
      _hasPermissions = new bool[](permissions.length);
      if (ownerOf(id) == operator) { // if operator is owner they have all permissions
        for (uint256 i = 0; i < permissions.length; i++) {
          _hasPermissions[i] = true;
        }
      } else {                       // if not the owner then check one by one
        NftPermission memory _nftPermission = idToNftPermission[id][operator];
        if (idToNft[id].lastOwnershipChange < _nftPermission.lastUpdated) {
          for (uint256 i = 0; i < permissions.length; i++) {
            if (_nftPermission.permissions._hasPermission(permissions[i])) {
              _hasPermissions[i] = true;
            }
          }
        }
      }
  }

  // Update `nft.xp` in memory. check for new `maxXp`. increase `totalXp`. 
  function _addXp(Nft memory nft, uint xp) private {
      nft.xp  += xp;
      if (nft.xp > maxXp) { maxXp = nft.xp; }
      totalXp += xp;
  }

  // Calculate share weighted by relative xp
  function _calcNftMint(
      int share, 
      uint xp
  ) private view returns (int) { // no xp accrual for minting
      uint relativeXp = xp.divWadDown(totalXp);
      if (share < 0) { relativeXp = 1e18 - relativeXp; }
      return wadMul(share, relativeXp.toInt256());
  }

  // Calculate xp accrual and share by relative xp
  function _calcNftBurn(
      int share, 
      uint xp
  ) private view returns (int, uint) {
      uint relativeXpToMax   = xp.divWadDown(maxXp);
      uint relativeXpToTotal = xp.divWadDown(totalXp);
      uint relativeXpNorm    = relativeXpToMax.divWadDown(relativeXpToTotal);
      uint oneMinusRank      = (1e18 - relativeXpToMax);
      int  multi             = oneMinusRank.divWadDown((totalSupply()*1e18)-relativeXpNorm).toInt256();
      int  relativeShare     = wadMul(multi, share);
      uint xpAccrual         = relativeShare.abs().divWadDown(relativeXpToMax);
      return (relativeShare, xpAccrual/1e18); 
  }

  function _calcXpReward(uint percent) private view returns (uint) {
    return dyad.totalSupply().mulWadDown(percent) / XP_NORM_FACTOR;
  }

  // Retrun the value of `eth` in DYAD
  function _eth2dyad(uint eth) private view returns (int) {
      return (eth/1e8).toInt256() * _getLatestEthPrice(); 
  }

  // ETH price in USD
  function _getLatestEthPrice() private view returns (int price) {
      ( , price, , , ) = oracle.latestRoundData();
  }

  function _beforeTokenTransfer(
      address _from,
      address _to,
      uint256 _id, 
      uint256 _batchSize 
  ) internal override {
      super._beforeTokenTransfer(_from, _to, _id, _batchSize);
      idToNft[_id].lastOwnershipChange = block.number;
  }
}

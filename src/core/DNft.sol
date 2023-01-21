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

  uint public constant MAX_SUPPLY                    = 10_000;     // Max supply of DNfts
  uint public constant MIN_COLLATERIZATION_RATIO     = 1.50e18;    // 15000 bps or 150%
  uint public constant MIN_PRICE_CHANGE_BETWEEN_SYNC = 0.001e18;   // 10    bps or 0.1%
  uint public constant MIN_TIME_BETWEEN_SYNC         = 10 minutes;
  int public immutable MIN_MINT_DYAD_DEPOSIT; // Deposit minimum to mint a new DNft

  uint public constant XP_NORM_FACTOR         = 1e16;
  uint public constant XP_MINT_REWARD         = 1_000;
  uint public constant XP_SYNC_REWARD         = 0.0004e18; // 4 bps    or 0.04%
  uint public constant XP_LIQUIDATION_REWARD  = 0.0004e18; // 4 bps    or 0.04%
  uint public constant XP_DIBS_BURN_REWARD    = 0.0003e18; // 3 bps    or 0.03%
  uint public constant XP_DIBS_MINT_REWARD    = 0.0002e18; // 2 bps    or 0.02%
  uint public constant XP_CLAIM_REWARD        = 0.0001e18; // 1 bps    or 0.01%
  int  public constant DIBS_MINT_SHARE_REWARD = 0.60e18;   // 6000 bps or 60%

  int  public lastEthPrice;           // ETH price from the last sync call
  int  public dyadDelta;              // Amount of dyad to mint/burn in this sync cycle
  int  public prevDyadDelta;          // Amount of dyad to mint/burn in the previous sync cycle
  uint public syncedBlock;            // Start of the current sync cycle
  uint public prevSyncedBlock;        // Start of the previous sync cycle
  uint public totalXp;                // Sum of all dNfts Xp
  uint public maxXp;                  // Max XP over all dNFTs
  uint public timeOfLastSync;


  struct Nft {
    uint xp;         // always inflationary
    int  deposit;    // deposited dyad
    uint withdrawal; // withdrawn dyad
    bool isActive;
  }

  struct NftPermission {
    uint8   permissions;
    uint248 lastUpdated; // The block number when it was last updated
  }

  enum Permission {
    ACTIVATE,
    DEACTIVATE,
    MOVE, 
    WITHDRAW, 
    REDEEM, 
    CLAIM 
  }

  mapping(uint => Nft)                               public idToNft;
  mapping(uint => mapping(uint => bool))             public claimed;        // id => (blockNumber => claimed)
  mapping(uint => mapping(address => NftPermission)) public nftPermissions; // id => (address => permission)
  mapping(uint => uint)                              public lastOwnershipChange;

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  event NftMinted          (address indexed to, uint indexed id);
  event DyadRedeemed       (address indexed to, uint indexed id, uint amount);
  event DyadWithdrawn      (uint indexed id, uint amount);
  event EthExchangedForDyad(uint indexed id, int amount);
  event DyadDepositBurned  (uint indexed id, uint amount);
  event DyadDepositMoved   (uint indexed from, uint indexed to, int amount);
  event Synced             (uint id);
  event Activated          (uint id);
  event Deactivated        (uint id);
  event NftLiquidated      (address indexed to, uint indexed id);

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
  error PriceChangeTooSmall            (int priceChange);
  error NotEnoughToCoverDepositMinimum (int amount);
  error NotEnoughToCoverNegativeDeposit(int amount);
  error CrTooLow                       (uint cr);
  error ExceedsDepositBalance          (int deposit);
  error ExceedsWithdrawalBalance       (uint amount);
  error FailedEthTransfer              (address to, uint amount);
  error AlreadyClaimed                 (uint id, uint syncedBlock);
  error AlreadySniped                  (uint id, uint syncedBlock);

  modifier exists(uint id) {
    ownerOf(id); _; // ownerOf reverts if dNft does not exist
  }
  modifier onlyOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotNFTOwner(id); _;
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
      int     _minMintDyadDeposit,
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
      MIN_MINT_DYAD_DEPOSIT = _minMintDyadDeposit;
      lastEthPrice          = _getLatestEthPrice();

      for (uint i = 0; i < _insiders.length; i++) {
        (uint id, Nft memory nft) = _mintNft(_insiders[i]); // insider DNfts do not require a deposit
        idToNft[id] = nft; 
      }
  }

  // Mint new DNft to `to` 
  function mint(address to) external payable {
      (uint id, Nft memory nft) = _mintNft(to); 
      int newDyad  = _eth2dyad(msg.value);
      if (newDyad < MIN_MINT_DYAD_DEPOSIT) { revert NotEnoughToCoverDepositMinimum(newDyad); }
      nft.deposit  = newDyad;
      nft.isActive = true;
      idToNft[id]  = nft;
  }

  // Mint new DNft to `to`
  function _mintNft(address to) private returns (uint, Nft memory) {
      uint id = totalSupply();
      if (id >= MAX_SUPPLY) { revert ReachedMaxSupply(); }
      _mint(to, id); // will revert on address(0)
      Nft memory nft; 
      _addXp(nft, XP_MINT_REWARD);
      emit NftMinted(to, id);
      return (id, nft);
  }

  // Permissionlessly exchange ETH for deposited DYAD
  function exchange(uint id) external exists(id) payable {
      int newDeposit       = _eth2dyad(msg.value);
      idToNft[id].deposit += newDeposit;
      emit EthExchangedForDyad(id, newDeposit);
  }

  // Deposit DYAD 
  function deposit(
      uint id,
      uint amount
  ) external exists(id) isActive(id) { 
      Nft storage nft = idToNft[id];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      unchecked {
      nft.withdrawal -= amount; // amount <= nft.withdrawal
      }
      nft.deposit    += amount.toInt256();
      bool success = dyad.transferFrom(msg.sender, address(this), amount);
      require(success);
      dyad.burn(address(this), amount);
  }

  // Move `amount` `from` one dNFT deposit `to` another dNFT deposit
  function move(
      uint _from,
      uint _to,
      int  _amount
  ) external onlyOwner(_from) exists(_to) isActive(_from) {
      require(_amount > 0);             // needed because _amount is int
      Nft storage from = idToNft[_from];
      if (_amount > from.deposit) { revert ExceedsDepositBalance(from.deposit); }
      unchecked {
      from.deposit         -= _amount;  // amount <= from.deposit
      }
      idToNft[_to].deposit += _amount;
      emit DyadDepositMoved(_from, _to, _amount);
  }

  // Withdraw DYAD from dNFT deposit
  function withdraw(
      uint from,
      address to, 
      uint amount 
  ) external onlyOwner(from) isActive(from) {
      uint collatVault    = address(this).balance/1e8 * _getLatestEthPrice().toUint256();
      uint totalWithdrawn = dyad.totalSupply() + amount;
      uint collatRatio    = collatVault.divWadDown(totalWithdrawn);
      if (collatRatio < MIN_COLLATERIZATION_RATIO) { revert CrTooLow(collatRatio); }
      Nft storage nft = idToNft[from];
      if (amount.toInt256() > nft.deposit) { revert ExceedsDepositBalance(nft.deposit); }
      unchecked {
      nft.deposit    -= amount.toInt256(); // amount <= nft.deposit
      }
      nft.withdrawal += amount; 
      dyad.mint(to, amount);
      emit DyadWithdrawn(from, amount);
  }

  // Redeem DYAD for ETH
  function redeem(
      uint from,
      address to,
      uint amount
  ) external nonReentrant onlyOwner(from) isActive(from) { 
      Nft storage nft = idToNft[from];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      unchecked {
      nft.withdrawal -= amount; // amount <= nft.withdrawal
      }
      dyad.burn(msg.sender, amount);
      uint eth = amount*1e8 / _getLatestEthPrice().toUint256();
      (bool success, ) = payable(to).call{value: eth}(""); // re-entrancy possible
      if (!success) { revert FailedEthTransfer(msg.sender, eth); }
      emit DyadRedeemed(msg.sender, from, amount);
  }

  // Determine amount of dyad to mint/burn in the next claim window
  function sync(uint id) external exists(id) isActive(id) {
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
  }

  // Claim DYAD from this sync window
  function claim(uint id) external onlyOwner(id) isActive(id) returns (int) {
      if (claimed[id][syncedBlock]) { revert AlreadyClaimed(id, syncedBlock); }
      claimed[id][syncedBlock] = true;
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
      return share;
  }

  // Snipe DYAD from previouse sync window to get a bonus
  function snipe(
      uint _from,
      uint _to
  ) external exists(_from) exists(_to) isActive(_from) isActive(_to) {
      if (claimed[_from][prevSyncedBlock]) { revert AlreadySniped(_from, prevSyncedBlock); }
      claimed[_from][prevSyncedBlock] = true;
      Nft memory from = idToNft[_from];
      Nft memory to   = idToNft[_to];
      if (prevDyadDelta > 0) {         
        int share     = _calcNftMint(prevDyadDelta, from.xp);
        from.deposit += wadMul(share, 1e18 - DIBS_MINT_SHARE_REWARD); 
        to.deposit   += wadMul(share, DIBS_MINT_SHARE_REWARD); 
        _addXp(to, _calcXpReward(XP_DIBS_MINT_REWARD));
      } else {                        
        (int share, uint xp) = _calcNftBurn(prevDyadDelta, from.xp);
        from.deposit += share;      
        _addXp(from, xp);
        _addXp(to, _calcXpReward(XP_DIBS_BURN_REWARD));
      }
      idToNft[_from] = from;
      idToNft[_to]   = to;
  }

  // Liquidate DNft by covering its deposit
  function liquidate(
      uint id, // no need to check `exists(id)` => (nft.deposit >= 0) will fail
      address to 
  ) external payable returns (uint) {
      Nft memory nft = idToNft[id];
      if (nft.deposit >= 0) { revert NotLiquidatable(id); }
      int newDyad = _eth2dyad(msg.value);
      if (newDyad < nft.deposit.abs().toInt256()) { revert NotEnoughToCoverNegativeDeposit(newDyad); }
      _burn(id);     // no need to delete idToNft[id] because it will be overwritten
      _mint(to, id); // no need to increment totalSupply, because burn + mint
      _addXp(nft, _calcXpReward(XP_LIQUIDATION_REWARD));
      nft.deposit += newDyad; 
      idToNft[id]  = nft;     
      emit NftLiquidated(to,  id); 
      return id;
  }

  // Activate inactive dNft
  function activate(uint id) external onlyOwner(id) isInactive(id) {
    idToNft[id].isActive = true;
    emit Activated(id);
  }

  // Deactivate active dNft
  function deactivate(uint id) external onlyOwner(id) isActive(id) {
    if (idToNft[id].withdrawal != 0) revert WithdrawalsNotZero(id);
    if (idToNft[id].deposit    <= 0) revert DepositIsNegative(id);
    idToNft[id].isActive = false;
    emit Deactivated(id);
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

  function hasPermission(
      uint256 _id,
      address _address,
      Permission _permission
  ) external view returns (bool) {
      if (ownerOf(_id) == _address) {
        return true;
      }
      NftPermission memory _nftPermission = nftPermissions[_id][_address];
      // If there was an ownership change after the permission was last updated, then the address doesn't have the permission
      return _nftPermission.permissions.hasPermission(_permission) && lastOwnershipChange[_id] < _nftPermission.lastUpdated;
  }

  function hasPermissions(
      uint256 _id,
      address _address,
      Permission[] calldata _permissions
  ) external view returns (bool[] memory _hasPermissions) {
      _hasPermissions = new bool[](_permissions.length);
      if (ownerOf(_id) == _address) {
        // If the address is the owner, then they have all permissions
        for (uint256 i = 0; i < _permissions.length; i++) {
          _hasPermissions[i] = true;
        }
      } else {
        // If it's not the owner, then check one by one
        NftPermission memory _nftPermission = nftPermissions[_id][_address];
        if (lastOwnershipChange[_id] < _nftPermission.lastUpdated) {
          for (uint256 i = 0; i < _permissions.length; i++) {
            if (_nftPermission.permissions.hasPermission(_permissions[i])) {
              _hasPermissions[i] = true;
            }
          }
        }
      }
  }
}

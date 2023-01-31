// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@solmate/src/utils/ReentrancyGuard.sol";
import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";
import {PermissionMath} from "../libraries/PermissionMath.sol";

contract DNft is ERC721Enumerable, ReentrancyGuard {
  using SafeTransferLib   for address;
  using SafeCast          for uint256;
  using SafeCast          for int256;
  using SignedMath        for int256;
  using FixedPointMathLib for uint256;
  using PermissionMath    for Permission[];
  using PermissionMath    for uint8;

  uint public immutable MAX_SUPPLY;            // Max supply of DNfts
  uint public immutable MIN_TIME_BETWEEN_SYNC; // Min elapsed time between syncs
  int  public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft
  uint public constant  MIN_COLLATERIZATION_RATIO = 1.50e18; // 15000 bps or 150%

  uint public constant XP_MINT_REWARD          = 1_000;
  int  public constant SNIPE_MINT_SHARE_REWARD = 0.60e18;   // 6000 bps or 60%
  // basis point rewards are always relative to `dyad.totalSupply()`
  uint public constant XP_SYNC_REWARD          = 0.0004e18; // 4 bps or 0.04%
  uint public constant XP_CLAIM_REWARD         = 0.0001e18; // 1 bps or 0.01%
  uint public constant XP_SNIPE_BURN_REWARD    = 0.0003e18; // 3 bps or 0.03%
  uint public constant XP_SNIPE_MINT_REWARD    = 0.0002e18; // 2 bps or 0.02%
  uint public constant XP_LIQUIDATION_REWARD   = 0.0004e18; // 4 bps or 0.04%

  int  public ethPrice;        // ETH price for the current sync cycle
  int  public dyadDelta;       // Amount of DYAD to mint/burn in the current sync cycle
  int  public prevDyadDelta;   // Amount of DYAD to mint/burn in the previous sync cycle
  uint public timeOfSync;      // Time, when the current sync cycle started
  uint public syncedBlock;     // Block number, when the current sync cycle started
  uint public prevSyncedBlock; // Block number, when the previous sync cycle started
  int  public totalDeposit;    // Sum of all dNFT Deposits
  uint public totalXp;         // Sum of all dNFT XPs
  uint public maxXp;           // Max XP over all dNFTs

  struct Nft {
    uint xp;                  // always inflationary
    int  deposit;             // deposited DYAD
    uint withdrawal;          // withdrawn DYAD
    uint lastOwnershipChange; // block number of the last ownership change
    bool isActive;
  }

  enum Permission { ACTIVATE, DEACTIVATE, EXCHANGE, DEPOSIT, MOVE, WITHDRAW, REDEEM, CLAIM }

  struct PermissionSet {
    address      operator;    // address that can perform the action
    Permission[] permissions; // permissions given to the operator
  }

  struct NftPermission {
    uint8   permissions; // bitmap of permissions
    uint248 lastUpdated; // block number of last update
  }

  mapping(uint => Nft)                               public idToNft;
  // id => (operator => NftPermission)
  mapping(uint => mapping(address => NftPermission)) public idToNftPermission; 
  // id => (blockNumber => claimed)
  mapping(uint => mapping(uint => bool))             public idToClaimed;       
  // id => (blockNumber)
  mapping(uint => uint)                              public idToLastDeposit; 

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  event Synced           (uint id);
  event XpUpdated        (uint indexed id, uint xp);
  event DepositUpdated   (uint indexed id, int  deposit);
  event WithdrawalUpdated(uint indexed id, uint withdrawal);
  event IsActiveUpdated  (uint indexed id, bool isActive);
  event Claimed          (uint indexed id, int  amount);
  event Deposited        (uint indexed id, uint amount);
  event Exchanged        (uint indexed id, int  amount);
  event Modified         (uint indexed id, PermissionSet[] permissions);
  event Withdrawn        (uint indexed from, address indexed to, uint amount);
  event Moved            (uint indexed from, uint indexed to, int amount);
  event Sniped           (uint indexed from, uint indexed to, int amount);
  event Minted           (address indexed to, uint indexed id);
  event Liquidated       (address indexed to, uint indexed id);
  event Redeemed         (address indexed to, uint indexed id, uint amount);

  error MaxSupply           ();
  error SyncTooSoon         ();
  error DyadTotalSupplyZero ();
  error DepositIsNegative   ();
  error EthPriceUnchanged   ();
  error DepositedInSameBlock();
  error CannotSnipeSelf     ();
  error AlreadySniped       ();
  error DepositTooLow       ();
  error NotLiquidatable     ();
  error DNftDoesNotExist    ();
  error NotNFTOwner         ();
  error WithdrawalsNotZero  ();
  error IsActive            ();
  error IsInactive          ();
  error ExceedsAverageTVL   ();
  error CrTooLow            ();
  error ExceedsDeposit      ();
  error ExceedsWithdrawal   ();
  error AlreadyClaimed      ();
  error MissingPermission   ();

  modifier exists(uint id) {
    if (!_exists(id)) revert DNftDoesNotExist(); _; 
  }
  modifier onlyOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotNFTOwner(); _;
  }
  modifier withPermission(uint id, Permission permission) {
    if (!hasPermission(id, msg.sender, permission)) revert MissingPermission(); _;
  }
  modifier isActive(uint id) {
    if (idToNft[id].isActive == false) revert IsInactive(); _;
  }
  modifier isInactive(uint id) {
    if (idToNft[id].isActive == true) revert IsActive(); _;
  }

  constructor(
      address _dyad,
      address _oracle, 
      uint    _maxSupply,
      uint    _minTimeBetweenSync,
      int     _minMintDyadDeposit, 
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
      MAX_SUPPLY            = _maxSupply;
      MIN_TIME_BETWEEN_SYNC = _minTimeBetweenSync;
      MIN_MINT_DYAD_DEPOSIT = _minMintDyadDeposit;
      ethPrice              = _getLatestEthPrice();

      for (uint i = 0; i < _insiders.length; i++) {
        // insiders do not require a DYAD deposit
        (uint id, Nft memory nft) = _mintNft(_insiders[i]); 
        idToNft[id] = nft; 
      }
  }

  // Mint new DNft to `to` 
  function mint(address to)
    external 
    payable 
    returns (uint) {
      int newDeposit = _eth2dyad(msg.value);
      if (newDeposit < MIN_MINT_DYAD_DEPOSIT) { revert DepositTooLow(); }
      (uint id, Nft memory nft) = _mintNft(to); 
      _addDeposit(id, nft, newDeposit);
      nft.isActive = true;
      idToNft[id]  = nft;
      return id;
  }

  // Mint new DNft to `to`
  function _mintNft(address to)
    private 
    returns (uint, Nft memory) {
      uint id = totalSupply();
      if (id >= MAX_SUPPLY) { revert MaxSupply(); }
      _mint(to, id); // will revert if `to` == address(0)
      emit Minted(to, id);
      Nft memory nft; 
      _addXp(id, nft, XP_MINT_REWARD);
      return (id, nft);
  }

  // Exchange ETH for DYAD deposit
  function exchange(uint id) 
    external 
      withPermission(id, Permission.EXCHANGE)
      isActive(id)
    payable
    returns (int) {
      idToLastDeposit[id] = block.number;
      int newDeposit      = _eth2dyad(msg.value);
      Nft memory nft = idToNft[id];
      _addDeposit(id, nft, newDeposit);
      idToNft[id] = nft;
      emit Exchanged(id, newDeposit);
      return newDeposit;
  }

  // Deposit DYAD 
  function deposit(uint id, uint amount)
    external 
      withPermission(id, Permission.DEPOSIT) 
      isActive(id) 
    { 
      idToLastDeposit[id] = block.number;
      dyad.burn(msg.sender, amount);
      Nft memory nft = idToNft[id];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawal(); }
      _subWithdrawal(id, nft, amount);
      _addDeposit   (id, nft, amount.toInt256());
      idToNft[id] = nft;
      emit Deposited(id, amount);
  }

  // Move `amount` `from` one dNFT deposit `to` another dNFT deposit
  function move(uint from, uint to, int amount) 
    external 
      withPermission(from, Permission.MOVE) 
    {
      require(amount > 0); // needed because amount is int
      Nft memory fromNft = idToNft[from];
      Nft memory   toNft = idToNft[to];
      if (amount > fromNft.deposit) { revert ExceedsDeposit(); }
      _subDeposit(from, fromNft, amount);
      _addDeposit(  to,   toNft, amount);
      idToNft[from] = fromNft;
      idToNft[to]   =   toNft;
      emit Moved(from, to, amount);
  }

  // Withdraw `amount` of deposited DYAD as an ERC-20 token from a dNFT
  function withdraw(uint from, address to, uint amount)
    external 
      withPermission(from, Permission.WITHDRAW)
      isActive(from) 
    returns (uint) {
      if (idToLastDeposit[from] == block.number) { revert DepositedInSameBlock(); } 
      Nft memory fromNft = idToNft[from];
      int _amount = amount.toInt256();  // amount is always >= 0
      if (_amount > fromNft.deposit) { revert ExceedsDeposit(); }
      uint collatVault    = address(this).balance * _getLatestEthPrice().toUint256() / 1e8;
      uint newCollatRatio = collatVault.divWadDown(dyad.totalSupply() + amount);
      if (newCollatRatio < MIN_COLLATERIZATION_RATIO) { revert CrTooLow(); }
      uint averageTVL    = collatVault / totalSupply();
      uint newWithdrawal = fromNft.withdrawal + amount;
      if (newWithdrawal > averageTVL) { revert ExceedsAverageTVL(); }
      _addWithdrawal(from, fromNft,  amount);
      _subDeposit   (from, fromNft, _amount);
      idToNft[from] = fromNft;
      dyad.mint(to, amount);
      emit Withdrawn(from, to, amount);
      return newCollatRatio;
  }

  // Redeem DYAD for ETH
  function redeem(uint from, address to, uint amount)
    external 
      nonReentrant 
      withPermission(from, Permission.REDEEM)
      isActive(from) 
    returns (uint) { 
      dyad.burn(msg.sender, amount);
      Nft storage fromNft = idToNft[from];
      if (amount > fromNft.withdrawal) { revert ExceedsWithdrawal(); }
      _subWithdrawal(from, fromNft, amount);
      uint eth = amount*1e8 / _getLatestEthPrice().toUint256();
      to.safeTransferETH(eth); // re-entrancy vector
      emit Redeemed(msg.sender, from, amount);
      return eth;
  }

  // Determine amount of DYAD to mint/burn in the next claim window
  function sync(uint id)
    external 
      isActive(id) 
    returns (int) {
      uint dyadTotalSupply = dyad.totalSupply(); 
      if (dyadTotalSupply == 0) { revert DyadTotalSupplyZero(); } 
      if (block.timestamp < timeOfSync + MIN_TIME_BETWEEN_SYNC) { revert SyncTooSoon(); }
      int newEthPrice = _getLatestEthPrice();
      if (newEthPrice == ethPrice) { revert EthPriceUnchanged(); }
      int priceChange = wadDiv(newEthPrice - ethPrice, ethPrice); 
      dyadDelta       = wadMul(dyadTotalSupply.toInt256(), priceChange);
      prevDyadDelta   = dyadDelta;
      timeOfSync      = block.timestamp;
      ethPrice        = newEthPrice; 
      prevSyncedBlock = syncedBlock;  // open new snipe window
      syncedBlock     = block.number; // open new claim window
      Nft memory nft  = idToNft[id];
      _addXp(id, nft, _calcXpReward(XP_SYNC_REWARD + priceChange.abs()));
      idToNft[id] = nft;
      emit Synced(id);
      return dyadDelta;
  }

  // Claim DYAD from the current sync window
  function claim(uint id)
    external 
      withPermission(id, Permission.CLAIM)
      isActive(id)
    returns (int) {
      if (idToClaimed[id][syncedBlock]) { revert AlreadyClaimed(); }
      idToClaimed[id][syncedBlock] = true;
      Nft memory nft = idToNft[id];
      int  allocation;
      uint newXp = _calcXpReward(XP_CLAIM_REWARD);
      if (dyadDelta > 0) {
        allocation = _calcMintAllocation(dyadDelta, nft);
        _addDeposit(id, nft, allocation);
      } else {
        uint xp;
        (allocation, xp) = _calcBurnAllocation(dyadDelta, nft);
        _subDeposit(id, nft, -allocation); // allocation is negative
        newXp += xp;
      }
      _addXp(id, nft, newXp);
      idToNft[id] = nft;
      emit Claimed(id, allocation);
      return allocation;
  }

  // Snipe DYAD from previouse sync window to get a bonus
  function snipe(uint from, uint to)
    external 
      isActive(from) 
      isActive(to) 
    returns (int) {
      if (from == to) { revert CannotSnipeSelf(); }
      if (idToClaimed[from][prevSyncedBlock]) { revert AlreadySniped(); }
      idToClaimed[from][prevSyncedBlock] = true;
      Nft memory fromNft = idToNft[from];
      Nft memory   toNft = idToNft[to];
      int allocation;
      if (prevDyadDelta > 0) {         
        allocation = _calcMintAllocation(prevDyadDelta, fromNft);
        _addDeposit(from, fromNft, wadMul(allocation, 1e18 - SNIPE_MINT_SHARE_REWARD));
        _addDeposit(  to,   toNft, wadMul(allocation, SNIPE_MINT_SHARE_REWARD));
        _addXp     (  to,   toNft, _calcXpReward(XP_SNIPE_MINT_REWARD));
      } else {                        
        uint xp;  
        (allocation, xp) = _calcBurnAllocation(prevDyadDelta, fromNft);
        _subDeposit(from, fromNft, -allocation); // allocation is negative
        _addXp     (from, fromNft, xp);
        _addXp     (  to,   toNft, _calcXpReward(XP_SNIPE_BURN_REWARD));
      }
      idToNft[from] = fromNft;
      idToNft[to]   =   toNft;
      emit Sniped(from, to, allocation);
      return allocation;
  }

  // Liquidate DNft by covering its deposit
  function liquidate(uint id, address to) 
    external 
    payable {
      Nft memory nft = idToNft[id];
      int currentDeposit = nft.deposit; // save gas
      if (currentDeposit >= 0) { revert NotLiquidatable(); }
      int newDeposit = _eth2dyad(msg.value);
      if (newDeposit < -currentDeposit) { revert DepositTooLow(); }
      _addDeposit(id, nft, newDeposit);
      _addXp     (id, nft, _calcXpReward(XP_LIQUIDATION_REWARD));
      idToNft[id] = nft;     
      _transfer(ownerOf(id), to, id);
      emit Liquidated(to, id); 
  }

  // Activate inactive dNFT
  function activate(uint id) 
    external 
      withPermission(id, Permission.ACTIVATE)
      isInactive(id) 
    {
      idToNft[id].isActive = true;
      emit IsActiveUpdated(id, true);
  }

  // Deactivate active dNFT
  function deactivate(uint id) 
    external 
      withPermission(id, Permission.DEACTIVATE)
      isActive(id) 
    {
      if (idToNft[id].withdrawal  > 0) revert WithdrawalsNotZero();
      if (idToNft[id].deposit    <= 0) revert DepositIsNegative();
      idToNft[id].isActive = false;
      emit IsActiveUpdated(id, false);
  }

  // Grant and revoke permissions
  function grant(uint _id, PermissionSet[] calldata _permissionSets) 
    external 
      onlyOwner(_id) 
    {
      uint248 _blockNumber = uint248(block.number);
      for (uint i = 0; i < _permissionSets.length; ) {
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

  // Check if operator has permission for dNFT with id
  function hasPermission(uint id, address operator, Permission permission) 
    public 
    view 
    returns (bool) {
      if (ownerOf(id) == operator) { return true; }
      NftPermission memory _nftPermission = idToNftPermission[id][operator];
      return _nftPermission.permissions._hasPermission(permission) &&
        // If there was an ownership change after the permission was last updated,
        // then the operator doesn't have the permission
        idToNft[id].lastOwnershipChange < _nftPermission.lastUpdated;
  }

  // Check if operator has permissions for dNFT with id
  function hasPermissions(uint id, address operator, Permission[] calldata permissions)
    external 
    view 
    returns (bool[] memory _hasPermissions) {
      _hasPermissions = new bool[](permissions.length);
      if (ownerOf(id) == operator) { // if operator is owner they have all permissions
        for (uint i = 0; i < permissions.length; i++) {
          _hasPermissions[i] = true;
        }
      } else {                       // if not the owner then check one by one
        NftPermission memory _nftPermission = idToNftPermission[id][operator];
        if (idToNft[id].lastOwnershipChange < _nftPermission.lastUpdated) {
          for (uint i = 0; i < permissions.length; i++) {
            if (_nftPermission.permissions._hasPermission(permissions[i])) {
              _hasPermissions[i] = true;
            }
          }
        }
      }
  }

  // Add `amount` to `nft.xp` in memory. check for new `maxXp` and increase `totalXp`. 
  function _addXp(uint id, Nft memory nft, uint amount) 
    private {
      nft.xp  += amount;
      totalXp += amount;
      if (nft.xp > maxXp) { maxXp = nft.xp; }
      emit XpUpdated(id, nft.xp);
  }

  // Add `amount` to `nft.deposit` in memory. update `totalDeposit` accordingly.
  function _addDeposit(uint id, Nft memory nft, int amount) 
    private {
      nft.deposit  += amount;
      totalDeposit += amount;
      emit DepositUpdated(id, nft.deposit);
  }

  // Subtract `amount` from `nft.deposit` in memory. update `totalDeposit` accordingly.
  function _subDeposit(uint id, Nft memory nft, int amount) 
    private {
      nft.deposit  -= amount;
      totalDeposit -= amount;
      emit DepositUpdated(id, nft.deposit);
  }

  // Add `amount` to `nft.withdrawal` in memory
  function _addWithdrawal(uint id, Nft memory nft, uint amount) 
    private {
      nft.withdrawal += amount;
      emit WithdrawalUpdated(id, nft.withdrawal);
  }

  // Subtract `amount` from `nft.withdrawal` in memory
  function _subWithdrawal(uint id, Nft memory nft, uint amount) 
    private {
      nft.withdrawal -= amount;
      emit WithdrawalUpdated(id, nft.withdrawal);
  }

  // Calculate this dNFTs mint allocation from all the `mintableDyad`
  function _calcMintAllocation(int mintableDyad, Nft memory nft) 
    private 
    view 
    returns (int) { // no xp accrual for minting
      if (nft.deposit < 0) revert DepositIsNegative();
      uint relativeXp      = nft.xp.divWadDown(totalXp);
      int  relativeDeposit = wadDiv(nft.deposit, totalDeposit);
      int  multi = (relativeXp.toInt256() + relativeDeposit) / 2;
      return wadMul(mintableDyad, multi);
  }

  // Calculate this dNFTs burn allocation from all the `burnableDyad` and the
  // xp reward it gets for burning it
  function _calcBurnAllocation(int burnableDyad, Nft memory nft) 
    private 
    view 
    returns (int, uint) {
      if (nft.deposit < 0) revert DepositIsNegative();
      uint relativeXpToMax   = nft.xp.divWadDown(maxXp);
      uint relativeXpToTotal = nft.xp.divWadDown(totalXp);
      uint relativeXpNorm    = relativeXpToMax.divWadDown(relativeXpToTotal);
      uint totalMinted       = dyad.totalSupply()+totalDeposit.toUint256();
      uint relativeMinted    = (nft.withdrawal+nft.deposit.toUint256()).divWadDown(totalMinted);
      uint oneMinusRank      = (1e18 - relativeXpToMax);
      int  multi             = oneMinusRank.divWadDown((totalSupply()*1e18)-relativeXpNorm).toInt256();
      multi                  = (relativeMinted.toInt256() + multi) / 2;
      int  relativeShare     = wadMul(multi, burnableDyad);
      uint epsilon           = 0.05e18; // xp accrual limit for very low xps 
      uint xpAccrual         = relativeShare.abs().divWadDown(relativeXpToMax+epsilon); 
      return (relativeShare, xpAccrual/1e18); 
  }

  // Return scaled down percentage of dyad supply as XP reward
  function _calcXpReward(uint percent) 
    private 
    view 
    returns (uint) {
      return totalDeposit.toUint256().mulWadDown(percent) / 1e16;
  }

  // Return the value of `eth` in DYAD
  function _eth2dyad(uint eth) 
    private 
    view 
    returns (int) {
      return (eth/1e8).toInt256() * _getLatestEthPrice(); 
  }

  // ETH price in USD
  function _getLatestEthPrice() 
    private 
    view 
    returns (int price) {
      ( , price, , , ) = oracle.latestRoundData();
  }

  // We have to set `lastOwnershipChange` in order to reset permissions
  function _beforeTokenTransfer(
      address _from,
      address _to,
      uint256 _id, 
      uint256 _batchSize 
  ) internal 
    override {
      super._beforeTokenTransfer(_from, _to, _id, _batchSize);
      idToNft[_id].lastOwnershipChange = block.number;
  }
}

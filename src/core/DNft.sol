// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@solmate/src/utils/ReentrancyGuard.sol";
import "@solmate/src/tokens/ERC721.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";

contract DNft is ERC721, ReentrancyGuard {
  using SafeCast          for uint256;
  using SafeCast          for int256;
  using SignedMath        for int256;
  using FixedPointMathLib for uint256;
  using LibString         for uint256;

  uint public constant MAX_SUPPLY                    = 10_000;
  uint public constant MIN_COLLATERIZATION_RATIO     = 1.50e18;    // 15000 bps or 150%
  uint public constant MIN_PRICE_CHANGE_BETWEEN_SYNC = 0.001e18;   // 10    bps or 0.1%
  uint public constant MIN_TIME_BETWEEN_SYNC         = 10 minutes;

  uint public constant XP_NORM_FACTOR        = 1e16;
  uint public constant XP_MINT_REWARD        = 1_000;
  uint public constant XP_SYNC_REWARD        = 0.0004e18; // 4 bps or 0.04%
  uint public constant XP_LIQUIDATION_REWARD = 0.0004e18; // 4 bps or 0.04%
  uint public constant XP_DIBS_BURN_REWARD   = 0.0003e18; // 3 bps or 0.03%
  uint public constant XP_DIBS_MINT_REWARD   = 0.0002e18; // 2 bps or 0.02%
  uint public constant XP_CLAIM_REWARD       = 0.0001e18; // 1 bps or 0.01%

  int public constant DIBS_MINT_SHARE_REWARD = 0.60e18;   // 6000 bps or 60%
  int public constant DIBS_BURN_PENALTY      = 0.01e18;   // 100  bps or 1%

  int public immutable MINT_MINIMUM;  // in DYAD

  uint public totalSupply;            // Number of dNfts in circulation
  int  public lastEthPrice;           // ETH price from the last sync call
  int  public dyadDelta;
  int  public prevDyadDelta;
  uint public syncedBlock;            // Last block, sync was called on
  uint public prevSyncedBlock;        // Second last block, sync was called on
  uint public totalXp;                // Sum of all dNfts Xp
  uint public maxXp;                  // Max XP over all dNFTs
  uint public timeOfLastSync;

  mapping(uint => Nft)  public idToNft;
  mapping(uint => mapping(uint => bool)) public claimed; // id => (blockNumber => claimed)

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  struct Nft {
    uint xp;
    int  deposit;
    uint withdrawal;
    bool isPaused;
  }

  event NftMinted          (address indexed to, uint indexed id);
  event DyadRedeemed       (address indexed to, uint indexed id, uint amount);
  event DyadWithdrawn      (uint indexed id, uint amount);
  event EthExchangedForDyad(uint indexed id, int amount);
  event DyadDepositBurned  (uint indexed id, uint amount);
  event DyadDepositMoved   (uint indexed from, uint indexed to, int amount);
  event Synced             (uint id);
  event Paused             (uint id);
  event Unpaused           (uint id);
  event NftLiquidated      (address indexed to, uint indexed id);

  error ReachedMaxSupply        ();
  error NoEthSupplied           ();
  error SyncTooSoon             ();
  error DNftDoesNotExist        (uint id);
  error NotNFTOwner             (uint id);
  error NotLiquidatable         (uint id);
  error WithdrawalsNotZero      (uint id);
  error DepositIsNegative       (uint id);
  error IsPaused                (uint id);
  error IsNotPaused             (uint id);
  error PriceChangeTooSmall     (int priceChange);
  error AddressZero             (address addr);
  error AmountZero              (uint amount);
  error UnderDepositMinimum     (int amount);
  error CrTooLow                (uint cr);
  error ExceedsDepositBalance   (int deposit);
  error ExceedsWithdrawalBalance(uint amount);
  error FailedEthTransfer       (address to, uint amount);
  error AlreadyClaimed          (uint id, uint syncedBlock);

  modifier addressNotZero(address addr) {
    if (addr == address(0)) revert AddressZero(addr); _;
  }
  modifier amountNotZero(uint amount) {
    if (amount == 0) revert AmountZero(amount); _;
  }
  modifier exists(uint id) {
    ownerOf(id); _; // ownerOf reverts if dNft does not exist
  }
  modifier onlyOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotNFTOwner(id); _;
  }
  modifier isPaused(uint id) {
    if (idToNft[id].isPaused == false) revert IsNotPaused(id); _;
  }
  modifier isNotPaused(uint id) {
    if (idToNft[id].isPaused == true) revert IsPaused(id); _;
  }

  constructor(
      address _dyad,
      address _oracle, 
      int     _mintMinimum,
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad         = Dyad(_dyad);
      oracle       = IAggregatorV3(_oracle);
      MINT_MINIMUM = _mintMinimum;
      lastEthPrice = _getLatestEthPrice();

      for (uint id = 0; id < _insiders.length; id++) {
        Nft memory nft = _mintNft(_insiders[id], id);
        nft.isPaused   = true;
        idToNft[id]    = nft;
      }
  }

  // Mint new DNft to `to` 
  function mint(address to) external payable {
      uint id = totalSupply; 
      Nft memory nft = _mintNft(to, id); 
      int newDyad = _eth2dyad(msg.value);
      if (newDyad < MINT_MINIMUM) { revert UnderDepositMinimum(newDyad); }
      nft.deposit = newDyad;
      idToNft[id] = nft;
  }

  // Mint new DNft to `to` with `id` id 
  function _mintNft(
      address to, // address(0) will make `_mint` fail
      uint id
  ) private returns (Nft memory) {
      if (id >= MAX_SUPPLY) { revert ReachedMaxSupply(); }
      totalSupply++;
      _mint(to, id); 
      Nft memory nft; // by default withdrawal = 0 and isPaused = false
      _updateXp(nft, XP_MINT_REWARD);
      emit NftMinted(to, id);
      return nft;
  }

  // Exchange ETH for deposited DYAD
  function exchange(uint id) external exists(id) payable {
      int newDeposit       = _eth2dyad(msg.value);
      idToNft[id].deposit += newDeposit;
      emit EthExchangedForDyad(id, newDeposit);
  }

  // Deposit DYAD 
  function deposit(
      uint id,
      uint amount
  ) external exists(id) isNotPaused(id) { 
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
  ) external onlyOwner(_from) exists(_to) isNotPaused(_from) {
      _move(_from, _to, _amount);
  }

  function _move(
      uint _from,
      uint _to,
      int  _amount
  ) private {
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
  ) external onlyOwner(from) isNotPaused(from) {
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
  ) external nonReentrant onlyOwner(from) isNotPaused(from) { 
      Nft storage nft = idToNft[from];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      unchecked {
      nft.withdrawal -= amount; // amount <= nft.withdrawal
      }
      dyad.burn(msg.sender, amount);
      uint eth = amount*1e8 / _getLatestEthPrice().toUint256();
      (bool success, ) = payable(to).call{value: eth}("");
      if (!success) { revert FailedEthTransfer(msg.sender, eth); }
      emit DyadRedeemed(msg.sender, from, amount);
  }

  function sync(uint id) external exists(id) isNotPaused(id) {
      int newEthPrice  = _getLatestEthPrice();
      int priceChange  = wadDiv(newEthPrice - lastEthPrice, lastEthPrice); 
      lastEthPrice     = newEthPrice; // makes calling `sync` multiple times in same block impossible
      uint priceChangeAbs = priceChange.abs();
      if (priceChangeAbs < MIN_PRICE_CHANGE_BETWEEN_SYNC) { revert PriceChangeTooSmall(priceChange); }
      if (block.timestamp < timeOfLastSync + MIN_TIME_BETWEEN_SYNC) { revert SyncTooSoon(); }
      timeOfLastSync   = block.timestamp;
      prevSyncedBlock  = syncedBlock;
      syncedBlock      = block.number;
      prevDyadDelta    = dyadDelta;
      dyadDelta        = wadMul(dyad.totalSupply().toInt256(), priceChange);
      uint newXp       = _calcXpReward(XP_SYNC_REWARD + priceChangeAbs);
      Nft memory nft   = idToNft[id];
      _updateXp(nft, newXp);
      idToNft[id]      = nft;
      emit Synced(id);
  }

  // Claim DYAD from this sync window
  function claim(uint id) external onlyOwner(id) isNotPaused(id) {
      if (claimed[id][syncedBlock]) { revert AlreadyClaimed(id, syncedBlock); }
      Nft memory nft  = idToNft[id];
      uint newXp = _calcXpReward(XP_CLAIM_REWARD);
      if (dyadDelta > 0) {
        int _share   = _calcMint(nft.xp, dyadDelta);
        nft.deposit += _share;
      } else {
        (uint xp, int relativeShare) = _calcBurn(nft.xp, dyadDelta);
        nft.deposit += relativeShare;
        newXp       += xp;
      }
      _updateXp(nft, newXp);
      idToNft[id] = nft;
      claimed[id][syncedBlock] = true;
  }

  // Snipe DYAD from previouse sync window to get a bonus
  function snipe(
      uint _from,
      uint _to
  ) external exists(_from) exists(_to) isNotPaused(_from) isNotPaused(_to) {
      if (claimed[_from][prevSyncedBlock]) { revert AlreadyClaimed(_from, prevSyncedBlock); }
      Nft memory from = idToNft[_from];
      Nft memory to   = idToNft[_to];
      if (prevDyadDelta > 0) {         // ETH price went up
        int share     = _calcMint(from.xp, prevDyadDelta);
        from.deposit += wadMul(share, 1e18 - DIBS_MINT_SHARE_REWARD); 
        to.deposit   += wadMul(share, DIBS_MINT_SHARE_REWARD); 
        _updateXp(to, _calcXpReward(XP_DIBS_MINT_REWARD));
      } else {                         // ETH price went down
        (uint xp, int share) = _calcBurn(from.xp, prevDyadDelta);
        from.deposit += share;      
        _updateXp(from, xp);
        _updateXp(to, _calcXpReward(XP_DIBS_BURN_REWARD));
      }
      idToNft[_from] = from;
      idToNft[_to]   = to;
      claimed[_from][prevSyncedBlock] = true;
  }

  // Liquidate dNFT by burning it and minting a new copy to `to`
  function liquidate(
      uint id,   // no check for `exists(id)`, because if it doesn't (nft.deposit == 0) is true
      address to 
  ) external payable returns (uint) {
      Nft memory nft = idToNft[id];
      if (nft.deposit >= 0) { revert NotLiquidatable(id); } // liquidatable if deposit is negative
      _burn(id);     // no need to delete idToNft[id] because it will be overwritten
      _mint(to, id); // no need to increment totalSupply, because burn + mint
      uint newXp   = dyad.totalSupply().mulWadDown(XP_LIQUIDATION_REWARD) / XP_NORM_FACTOR;
      _updateXp(nft, newXp);
      int newDyad     = _eth2dyad(msg.value);
      if (newDyad < nft.deposit.abs().toInt256()) { revert UnderDepositMinimum(newDyad); }
      nft.deposit += newDyad; // nft.deposit must be >= 0 now
      idToNft[id]  = nft;     // withdrawal stays exactly as it was
      emit NftLiquidated(to,  id); 
      return id;
  }

  function pause(uint id) external onlyOwner(id) isNotPaused(id) {
    if (idToNft[id].withdrawal != 0) revert WithdrawalsNotZero(id);
    if (idToNft[id].deposit    <= 0) revert DepositIsNegative(id);
    idToNft[id].isPaused = true;
    emit Paused(id);
  }

  function unpause(uint id) external onlyOwner(id) isPaused(id) {
    idToNft[id].isPaused = false;
    emit Unpaused(id);
  }

  // Update `nft.xp` in memory. check for new `maxXp`. increase `totalXp`. 
  function _updateXp(Nft memory nft, uint xp) private {
      nft.xp  += xp;
      if (nft.xp > maxXp) { maxXp = nft.xp; }
      totalXp += xp;
  }

  // Calculate share weighted by relative xp
  function _calcMint(
      uint xp, 
      int share
  ) private view returns (int) { // no xp accrual for minting
      uint relativeXp = xp.divWadDown(totalXp);
      if (share < 0) { relativeXp = 1e18 - relativeXp; }
      return wadMul(share, relativeXp.toInt256());
  }

  // Calculate xp accrual and share by relative xp
  function _calcBurn(
      uint xp,
      int share
  ) private view returns (uint, int) {
      uint relativeXpToMax   = xp.divWadDown(maxXp);
      uint relativeXpToTotal = xp.divWadDown(totalXp);
      uint relativeXpNorm    = relativeXpToTotal.divWadDown(relativeXpToMax);
      uint oneMinusRank      = (1e18 - relativeXpToMax);
      int  multi             = oneMinusRank.divWadDown(totalSupply*1e18-relativeXpNorm).toInt256();
      int  allocation        = wadMul(multi, share);
      uint xpAccrual         = allocation.abs().divWadDown(relativeXpToMax);
      return (xpAccrual/1e18, allocation); 
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

  function tokenURI(uint256 id) exists(id) public view override returns (string memory) { 
    return string.concat("https://dyad.xyz.com/api/dnfts/", id.toString());
  }
}

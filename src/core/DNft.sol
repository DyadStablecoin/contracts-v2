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

  uint public constant MAX_SUPPLY                = 10_000;
  uint public constant MIN_COLLATERIZATION_RATIO = 150*1e16; // 15000 bps or 150%
  uint public constant SYNC_MIN_PRICE_CHANGE     = 1e15;     // 10    bps or 0.1%

  uint public constant XP_NORM_FACTOR        = 1e16;
  uint public constant XP_MINT_REWARD        = 1_000;
  uint public constant XP_SYNC_REWARD        = 4e15;         // 4 bps or 0.04%
  uint public constant XP_LIQUIDATION_REWARD = 4e15;         // 4 bps or 0.04%
  uint public constant XP_DIBS_BURN_REWARD   = 3e15;         // 3 bps or 0.03%
  uint public constant XP_DIBS_MINT_REWARD   = 2e15;         // 2 bps or 0.02%
  uint public constant XP_CLAIM_REWARD       = 1e15;         // 1 bps or 0.01%

  uint public immutable DEPOSIT_MIMIMUM;

  uint public totalSupply;
  int  public lastEthPrice;           // ETH price from the last sync call
  uint public totalXp;                // Sum of all dNfts Xp
  int  public dyadDelta;
  int  public prevDyadDelta;
  uint public syncedBlock;            // Last block sync was called on
  uint public prevSyncedBlock;        // Second last block sync was called on

  mapping(uint => Nft)  public idToNft;
  mapping(uint => mapping(uint => bool)) public claimed; // id => (blockNumber => claimed)

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  struct Nft {
    uint xp;
    int  deposit;
    uint withdrawal;
  }

  event NftMinted        (address indexed to, uint indexed id);
  event DyadRedeemed     (address indexed to, uint indexed id, uint amount);
  event DyadWithdrawn    (uint indexed id, uint amount);
  event DyadDeposited    (uint indexed id, uint amount);
  event DyadDepositBurned(uint indexed id, uint amount);
  event DyadDepositMoved (uint indexed from, uint indexed to, int amount);
  event Synced           (uint id);
  event NftLiquidated    (address indexed to, uint indexed id);

  error ReachedMaxSupply        ();
  error NoEthSupplied           ();
  error DNftDoesNotExist        (uint id);
  error NotNFTOwner             (uint id);
  error NotLiquidatable         (uint id);
  error PriceChangeTooSmall     (int priceChange);
  error AddressZero             (address addr);
  error AmountZero              (uint amount);
  error AmountLessThanMimimum   (uint amount);
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

  constructor(
      address _dyad,
      address _oracle, 
      uint    _depositMinimum,
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad            = Dyad(_dyad);
      oracle          = IAggregatorV3(_oracle);
      DEPOSIT_MIMIMUM = _depositMinimum;
      lastEthPrice    = _getLatestEthPrice();

      for (uint i = 0; i < _insiders.length; ) { 
        _mintNft(_insiders[i], totalSupply++);
        unchecked { ++i; }
      }
  }

  // Mint new DNft to `to` 
  function mint(address to) external payable {
      uint id = totalSupply++; 
      _mintNft(to, id); 
      _deposit(id, DEPOSIT_MIMIMUM);
  }

  // Mint new DNft to `to` with `id` id 
  function _mintNft(
      address to,
      uint id
  ) private {
      if (id >= MAX_SUPPLY) { revert ReachedMaxSupply(); }
      _mint(to, id); 
      idToNft[id].xp = XP_MINT_REWARD;
      totalXp       += XP_MINT_REWARD;
      emit NftMinted(to, id);
  }

  // Convert ETH to deposited DYAD
  function convert(uint id) external exists(id) payable {
      _deposit(id, 0);
  }

  // Deposit at least `minAmount` of DYAD for ETH
  function _deposit(
      uint id,
      uint minAmount
  ) private returns (uint) {
      uint newDyad = msg.value/1e8 * _getLatestEthPrice().toUint256();
      if (newDyad < minAmount) { revert AmountLessThanMimimum(newDyad); }
      idToNft[id].deposit += newDyad.toInt256();
      emit DyadDeposited(id, newDyad);
      return newDyad;
  }

  // Deposit DYAD 
  function deposit(
      uint id,
      uint amount
  ) external exists(id) {
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
  ) external onlyOwner(_from) exists(_to) {
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
  ) external onlyOwner(from) {
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
  ) external nonReentrant onlyOwner(from) {
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

  function sync(uint id) external exists(id) {
      int  priceChange    = wadDiv(_getLatestEthPrice() - lastEthPrice, lastEthPrice); 
      uint priceChangeAbs = priceChange.abs();
      if (priceChangeAbs < SYNC_MIN_PRICE_CHANGE) { revert PriceChangeTooSmall(priceChange); }
      prevSyncedBlock  = syncedBlock;
      syncedBlock      = block.number;
      prevDyadDelta    = dyadDelta;
      dyadDelta        = wadMul(dyad.totalSupply().toInt256(), priceChange);
      uint xp          = _calcXpReward(XP_SYNC_REWARD + priceChangeAbs);
      idToNft[id].xp  += xp;
      totalXp         += xp;
      emit Synced(id);
  }

  // Claim DYAD from this sync window
  function claim(uint id) external onlyOwner(id) {
      if (claimed[id][syncedBlock]) { revert AlreadyClaimed(id, syncedBlock); }
      Nft storage nft  = idToNft[id];
      int share        = _calcShare(dyadDelta, nft.xp);
      nft.deposit     += share;
      uint xpAccrual   = dyad.totalSupply().mulWadDown(XP_CLAIM_REWARD) / XP_NORM_FACTOR;
      uint xp          = _calcXpReward(XP_CLAIM_REWARD);
      if (dyadDelta < 0) { xpAccrual += _calcBurnXpReward(nft.xp, share); }
      nft.xp          += xp;
      totalXp         += xp;
      claimed[id][syncedBlock] = true;
  }

  // Claim DYAD from previouse sync window to get a bonus
  function dibs(
      uint _from,
      uint _to
  ) external exists(_from) exists(_to) {
      if (claimed[_from][prevSyncedBlock]) { revert AlreadyClaimed(_from, prevSyncedBlock); }
      int share         = _calcShare(prevDyadDelta, idToNft[_from].xp);
      prevDyadDelta > 0 ? _dibsMint(_from, _to, share)   // prevDyadDelta != 0
                        : _dibsBurn(_from, _to, share);
      claimed[_from][prevSyncedBlock] = true;
  }

  function _dibsMint(
      uint _from, 
      uint _to,
      int _share
  ) private {
      idToNft[_from].deposit += wadMul(_share, 0.75e18); // 25% 
      Nft storage to = idToNft[_to];
      to.deposit             += wadMul(_share, 0.25e18); // 75%
      uint xp  = _calcXpReward(XP_DIBS_MINT_REWARD);
      to.xp   += xp;
      totalXp += xp;
  }

  function _dibsBurn(
      uint _from, 
      uint _to,
      int _share
  ) private {
      idToNft[_from].deposit += _share; 
      int toMove = wadMul(_share, 0.10e17); // 1%
      if (toMove > idToNft[_to].deposit) { _move(_from, _to, toMove); }
      uint xp          = _calcXpReward(XP_DIBS_BURN_REWARD);
      xp              += _calcBurnXpReward(idToNft[_to].xp, _share); 
      idToNft[_to].xp += xp;
      totalXp         += xp;
  }

  function _calcXpReward(uint percent) private view returns (uint) {
    return dyad.totalSupply().mulWadDown(percent) / XP_NORM_FACTOR;
  }

  // Calculate xp accrual for burning `share` of DYAD weighted by relative `xp`
  function _calcBurnXpReward(uint xp, int share) private view returns (uint) {
      uint relativeXp  = xp.divWadDown(totalXp);
      return ((1e18 - relativeXp) * share.toUint256()); 
  }

  // Return share of `_amount` weighted by `xp`
  function _calcShare(
      int _amount,
      uint _xp
  ) private view returns (int) {
      int relativeXp = wadDiv(_xp.toInt256(), totalXp.toInt256());
      if (_amount < 0) { relativeXp = 1e18 - relativeXp; }
      return wadMul(_amount, relativeXp);
  }

  // Liquidate dNFT by burning it and minting a new copy to `to`
  function liquidate(
      uint id,   // no check for `exists(id)`, because if it doesn't (nft.deposit == 0) is true
      address to 
  ) external payable returns (uint) {
      Nft memory nft = idToNft[id];
      if (nft.deposit >= 0) { revert NotLiquidatable(id); }
      _burn(id);        // no need to delete idToNft[id] because it will be overwritten
      _mintNft(to, id); // no need to increment totalSupply, because burn + mint
      uint minDeposit;
      if (nft.deposit < 0) { minDeposit = nft.deposit.abs(); }
      uint xp      = dyad.totalSupply().mulWadDown(XP_LIQUIDATION_REWARD) / XP_NORM_FACTOR;
      nft.xp      += xp;
      totalXp     += xp;
      nft.deposit += _deposit(id, minDeposit).toInt256();
      idToNft[id] = nft;
      emit NftLiquidated(to,  id); 
      return id;
  }

  // ETH price in USD
  function _getLatestEthPrice() private view returns (int price) {
    ( , price, , , ) = oracle.latestRoundData();
  }

  function tokenURI(uint256 id) exists(id) public view override returns (string memory) { 
    return string.concat("https://dyad.xyz.com/api/dnfts/", id.toString());
  }
}

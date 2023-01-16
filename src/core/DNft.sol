// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@solmate/src/utils/ReentrancyGuard.sol";
import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";

contract DNft is ERC721Enumerable, ReentrancyGuard {
  using SafeCast          for uint256;
  using SafeCast          for int256;
  using SignedMath        for int256;
  using FixedPointMathLib for uint256;

  uint public constant MAX_SUPPLY      = 10_000;

  uint public constant XP_SYNC_REWARD        = 1_000;
  uint public constant XP_LIQUIDATION_REWARD = 600;
  uint public constant XP_MINT_REWARD        = 400;
  uint public constant XP_DIBS_BURN_REWARD   = 300;
  uint public constant XP_DIBS_MINT_REWARD   = 200;
  uint public constant XP_CLAIM_REWARD       = 50;

  uint public immutable DEPOSIT_MIMIMUM;

  int  public lastEthPrice;
  uint public totalXp;

  int  public dyadDelta;
  int  public prevDyadDelta;

  uint public syncedBlock;
  uint public prevSyncedBlock;

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
  event DyadDepositBurned(uint indexed id, uint amount);
  event DyadDepositMoved (uint indexed from, uint indexed to, int amount);
  event DyadMinted       (uint indexed id, uint amount);
  event Synced           (uint id);
  event NftLiquidated    (address indexed from, address indexed to, uint indexed id);

  error ReachedMaxSupply        ();
  error NoEthSupplied           ();
  error DNftDoesNotExist        (uint id);
  error NotNFTOwner             (uint id);
  error NotLiquidatable         (uint id);
  error AddressZero             (address addr);
  error AmountZero              (uint amount);
  error NotReachedMinAmount     (uint amount);
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
  modifier dNftExists(uint id) {
    if (!_exists(id)) revert DNftDoesNotExist(id); _;
  }
  modifier isDNftOwner(uint id) {
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
        _mintNft(_insiders[i], i);
        unchecked { ++i; }
      }
  }

  // Mint new DNft to `to` 
  function mint(address to) external payable {
      uint id = totalSupply();
      _mintNft(to, id); 
      _mintDyad(id, DEPOSIT_MIMIMUM);
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

  // Deposit DYAD for ETH
  function deposit(uint id) external dNftExists(id) payable {
      _mintDyad(id, 0);
  }

  // Deposit at least `minAmount` of DYAD for ETH
  function _mintDyad(
      uint id,
      uint minAmount
  ) private returns (uint) {
      uint newDyad = msg.value/1e8 * _getLatestEthPrice().toUint256();
      if (newDyad < minAmount) { revert NotReachedMinAmount(newDyad); }
      dyad.mint(address(this), newDyad);
      idToNft[id].deposit += newDyad.toInt256();
      emit DyadMinted(id, newDyad);
      return newDyad;
  }

  // Deposit DYAD for DYAD
  function deposit(
      uint id,
      uint amount
  ) external dNftExists(id) {
      Nft storage nft = idToNft[id];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      dyad.burn(msg.sender, amount);
      unchecked {
      nft.withdrawal -= amount; // amount <= nft.withdrawal
      }
      nft.deposit    += amount.toInt256();
  }

  // Move `amount` `from` one dNFT deposit `to` another dNFT deposit
  function move(
      uint _from,
      uint _to,
      int  _amount
  ) external isDNftOwner(_from) {
      _move(_from, _to, _amount);
  }

  function _move(
      uint _from,
      uint _to,
      int  _amount
  ) private {
      require(_amount > 0);
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
      uint id,
      uint amount
  ) external isDNftOwner(id) {
      Nft storage nft = idToNft[id];
      if (amount.toInt256() > nft.deposit) { revert ExceedsDepositBalance(nft.deposit); }
      unchecked {
      nft.deposit    -= amount.toInt256(); // amount <= nft.deposit
      }
      nft.withdrawal += amount; 
      dyad.mint(msg.sender, amount);
      emit DyadWithdrawn(id, amount);
  }

  // Redeem DYAD for ETH
  function redeem(
      uint id,
      uint amount
  ) external nonReentrant isDNftOwner(id) {
      Nft storage nft = idToNft[id];
      if (amount > nft.withdrawal) { revert ExceedsWithdrawalBalance(amount); }
      unchecked {
      nft.withdrawal -= amount; // amount <= nft.withdrawal
      }
      dyad.burn(msg.sender, amount);
      uint eth = amount*1e8 / _getLatestEthPrice().toUint256();
      (bool success, ) = payable(msg.sender).call{value: eth}("");
      if (!success) { revert FailedEthTransfer(msg.sender, eth); }
      emit DyadRedeemed(msg.sender, id, amount);
  }

  function sync(uint id) external dNftExists(id) {
      prevSyncedBlock = syncedBlock;
      syncedBlock     = block.number;
      int priceChange = wadDiv(_getLatestEthPrice() - lastEthPrice, lastEthPrice); 
      uint newXp      = XP_SYNC_REWARD.mulWadUp(priceChange.abs());
      idToNft[id].xp += newXp;
      totalXp        += newXp;
      prevDyadDelta   = dyadDelta;
      dyadDelta       = wadMul(dyad.totalSupply().toInt256(), priceChange);
      emit Synced(id);
  }

  function claim(uint id) external isDNftOwner(id) {
      if (claimed[id][syncedBlock]) { revert AlreadyClaimed(id, syncedBlock); }
      Nft storage nft  = idToNft[id];
      nft.deposit     += _calcShare(dyadDelta, nft.xp);
      nft.xp          += XP_CLAIM_REWARD;
      totalXp         += XP_CLAIM_REWARD;
      claimed[id][syncedBlock] = true;
  }

  // Claim DYAD from the previouse sync window for other dNFTs to get a bonus
  function dibs(
      uint _from,
      uint _to
  ) external dNftExists(_from) dNftExists(_to) {
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
      to.xp   += XP_DIBS_MINT_REWARD;
      totalXp += XP_DIBS_MINT_REWARD;
  }

  function _dibsBurn(
      uint _from, 
      uint _to,
      int _share
  ) private {
      idToNft[_from].deposit += _share; 
      int toMove = wadMul(_share, 0.10e18); // 10%
      if (toMove > idToNft[_to].deposit) { _move(_from, _to, toMove); }
      idToNft[_to].xp += XP_DIBS_BURN_REWARD;
      totalXp         += XP_DIBS_BURN_REWARD;
  }

  // Liquidate dNFT by burning it and minting a new copy to `to`
  function liquidate(
      uint id,
      address to
  ) external addressNotZero(to) payable returns (uint) {
      Nft memory nft = idToNft[id];
      if (nft.deposit >= 0) { revert NotLiquidatable(id); }
      address owner  = ownerOf(id);
      _burn(id); 
      delete idToNft[id];
      _mintCopy(to, nft, id);
      idToNft[id].xp += XP_LIQUIDATION_REWARD;
      totalXp        += XP_LIQUIDATION_REWARD;
      emit NftLiquidated(owner, to,  id); 
      return id;
  }

  // Mint nft with `id` to `to` with the same xp and withdrawn amount as `nft`
  function _mintCopy(
      address to,
      Nft memory nft, 
      uint id
  ) private returns (uint) { 
      _mintNft(to, id);
      Nft storage newNft = idToNft[id];
      uint minDeposit;
      if (nft.deposit < 0) { minDeposit = nft.deposit.abs(); }
      int newDeposit    = _mintDyad(id, minDeposit).toInt256();
      newNft.deposit    = newDeposit + nft.deposit;
      newNft.xp         = nft.xp;
      newNft.withdrawal = nft.withdrawal;
      return id;
  }

  // return share of `_amount` weighted by `xp`
  function _calcShare(
      int _amount,
      uint _xp
  ) private view returns (int) {
      int relativeXp = wadDiv(_xp.toInt256(), totalXp.toInt256());
      if (_amount < 0) { relativeXp = 1e18 - relativeXp; }
      return wadMul(_amount, relativeXp);
  }

  // ETH price in USD
  function _getLatestEthPrice() private view returns (int newEthPrice) {
    ( , newEthPrice, , , ) = oracle.latestRoundData();
  }
}

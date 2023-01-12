// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";

contract DNft is ERC721Enumerable, ReentrancyGuard {
  using SafeCast for int256;

  uint public constant MAX_SUPPLY = 10_000;
  uint public immutable DEPOSIT_MIMIMUM;

  mapping(uint256 => Nft) public idToNft;

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  struct Nft {
    uint xp;
    uint deposit;
    uint withdrawal;
    uint credit;
    uint creditScore;
  }

  event NftMinted        (address indexed to, uint indexed id);
  event DyadRedeemed     (address indexed to, uint indexed id, uint amount);
  event DyadWithdrawn    (uint indexed id, uint amount);
  event DyadDepositBurned(uint indexed id, uint amount);
  event DyadDepositMoved (uint indexed from, uint indexed to, uint amount);


  error ReachedMaxSupply        ();
  error NoEthSupplied           ();
  error DNftDoesNotExist        (uint id);
  error NotNFTOwner             (uint id);
  error AddressZero             (address addr);
  error AmountZero              (uint amount);
  error NotReachedMinAmount     (uint amount);
  error ExceedsDepositBalance   (uint amount);
  error ExceedsWithdrawalBalance(uint amount);
  error CannotMoveDepositToSelf (uint from, uint to);
  error FailedEthTransfer       (address to, uint amount);

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

    for (uint i = 0; i < _insiders.length; ) { 
      _mintNft(_insiders[i], i);
      unchecked { ++i; }
    }
  }

  // Mint new DNft to `to` 
  function mintNft(address to) external addressNotZero(to) payable {
    uint id = totalSupply();
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
    emit NftMinted(to, id);
  }

  function deposit(uint id) external dNftExists(id) payable {
    _deposit(id, 0);
  }

  function _deposit(uint id, uint minAmount) private {
    if (msg.value == 0) { revert NoEthSupplied(); }
    uint newDeposit = msg.value/100000000 * _getLatestEthPrice();
    if (newDeposit < minAmount) { revert NotReachedMinAmount(newDeposit); }
    idToNft[id].deposit += newDeposit;
  }

  // Move `amount` `from` one dNFT deposit `to` another dNFT deposit
  function moveDeposit(
      uint _from,
      uint _to,
      uint _amount
  ) external isDNftOwner(_from) {
      if (_from == _to) { revert CannotMoveDepositToSelf(_from, _to); }
      Nft storage from = idToNft[_from];
      if (_amount > from.deposit) { revert ExceedsDepositBalance(_amount); }
      unchecked {
      from.deposit         -= _amount;  // amount <= from.deposit
      }
      idToNft[_to].deposit += _amount;
      emit DyadDepositMoved(_from, _to, _amount);
  }

  function withdraw(
      uint id,
      uint amount
  ) external isDNftOwner(id) {
      Nft storage nft = idToNft[id];
      if (amount > nft.deposit) { revert ExceedsDepositBalance(amount); }
      unchecked {
      nft.deposit    -= amount; // amount <= nft.deposit
      }
      nft.withdrawal += amount; 
      dyad.mint(msg.sender, amount);
      emit DyadWithdrawn(id, amount);
  }

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
      uint eth = amount*100000000 / _getLatestEthPrice();
      (bool success, ) = payable(msg.sender).call{value: eth}("");
      if (!success) { revert FailedEthTransfer(msg.sender, eth); }
      emit DyadRedeemed(msg.sender, id, amount);
  }

  // Burn deposit for xp
  function burn(
    uint id,
    uint amount
  ) external isDNftOwner(id) {
    Nft storage nft = idToNft[id];
    if (amount > nft.deposit) { revert ExceedsDepositBalance(amount); }
    unchecked {
    nft.deposit -= amount;  // amount <= nft.deposit
    }
    nft.xp += amount;
    emit DyadDepositBurned(id, amount);
  }

  // ETH price in USD
  function _getLatestEthPrice() private view returns (uint) {
    ( , int newEthPrice, , , ) = oracle.latestRoundData();
    return newEthPrice.toUint256();
  }
}

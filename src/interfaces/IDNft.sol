// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  error ReachedMaxSupply        ();
  error NoEthSupplied           ();
  error DNftDoesNotExist        (uint id);
  error NotNFTOwner             (uint id);
  error AddressZero             (address addr);
  error AmountZero              (uint amount);
  error NotReachedMinAmount     (uint amount);
  error ExceedsDepositBalance   (int deposit);
  error ExceedsWithdrawalBalance(uint amount);
  error FailedEthTransfer       (address to, uint amount);

  struct Nft {
    uint xp;
    int  deposit;
    uint withdrawal;
  }

  function XP_MINT_REWARD() external view returns (uint);
  function XP_SYNC_REWARD() external view returns (uint);

  function dyadDelta() external view returns (int);
  function totalXp()   external view returns (uint);
  function idToNft(uint id) external view returns (Nft memory);

  function mint    (address to) external payable;
  function deposit (uint id) external payable;
  function deposit (uint id, uint amount) external;
  function move    (uint from, uint to, int amount) external payable;
  function withdraw(uint id, uint amount) external payable;
  function redeem  (uint id, uint amount) external payable;
  function sync    (uint id) external payable;
  function claim   (uint id) external payable;

  function MAX_SUPPLY() external pure returns (uint);
  function DEPOSIT_MIMIMUM() external pure returns (uint);

  // ERC721
  function ownerOf(uint tokenId) external view returns (address);
  function balanceOf(address owner) external view returns (int);
  function totalSupply() external view returns (uint);
}

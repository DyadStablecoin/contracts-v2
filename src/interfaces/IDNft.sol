// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
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

  struct Nft {
    uint xp;
    int  deposit;
    uint withdrawal;
  }

  // view functions
  function XP_MINT_REWARD() external view returns (uint);
  function XP_SYNC_REWARD() external view returns (uint);
  function idToNft(uint id) external view returns (Nft memory);
  function dyadDelta()      external view returns (int);
  function totalXp()        external view returns (uint);
  function syncedBlock()    external view returns (uint);
  function lastEthPrice()   external view returns (uint);

  // state changing functions
  function mint    (address to) external payable;
  function exchange(uint id) external payable;
  function deposit (uint id, uint amount) external;
  function move    (uint from, uint to, int amount) external;
  function withdraw(uint from, address to, uint amount) external;
  function redeem  (uint from, address to, uint amount) external;
  function sync    (uint id) external;
  function claim   (uint id) external;
  function dibs    (uint from, uint to) external;

  function MAX_SUPPLY() external pure returns (uint);
  function DEPOSIT_MIMIMUM() external pure returns (uint);

  // ERC721
  function ownerOf(uint tokenId) external view returns (address);
  function balanceOf(address owner) external view returns (int);
  function totalSupply() external view returns (uint);
}

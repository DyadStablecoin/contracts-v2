// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  enum Permission { ACTIVATE, DEACTIVATE, MOVE, WITHDRAW, REDEEM, CLAIM }

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
  error NotAuthorized                  (uint id, Permission permission);

  struct Nft {
    uint xp;
    int  deposit;
    uint withdrawal;
  }

  // view functions
  function XP_MINT_REWARD() external view returns (uint);
  function XP_SYNC_REWARD() external view returns (uint);
  function maxXp()          external view returns (uint);
  function idToNft(uint id) external view returns (Nft memory);
  function dyadDelta()      external view returns (int);
  function totalXp()        external view returns (uint);
  function syncedBlock()    external view returns (uint);
  function prevSyncedBlock()external view returns (uint);
  function lastEthPrice()   external view returns (uint);

  // state changing functions
  function mint      (address to) external payable;
  function exchange  (uint id) external payable;
  function deposit   (uint id, uint amount) external;
  function move      (uint from, uint to, int amount) external;
  function withdraw  (uint from, address to, uint amount) external;
  function redeem    (uint from, address to, uint amount) external;
  function sync      (uint id) external;
  function claim     (uint id) external returns (int);
  function snipe     (uint from, uint to) external;
  function activate  (uint id) external;
  function deactivate(uint id) external;

  function MAX_SUPPLY() external pure returns (uint);
  function MINT_MINIMUM() external pure returns (uint);

  // ERC721
  function ownerOf(uint tokenId) external view returns (address);
  function balanceOf(address owner) external view returns (int);
  function totalSupply() external view returns (uint);
  function approve(address spender, uint256 id) external;
}

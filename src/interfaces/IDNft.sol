// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

enum Permission { ACTIVATE, DEACTIVATE, MOVE, WITHDRAW, REDEEM, CLAIM }

struct PermissionSet {
  address operator;         // The address of the operator
  Permission[] permissions; // The permissions given to the operator
}

interface IDNft {
  struct NftPermission {
    uint8   permissions;
    uint248 lastUpdated; // The block number when it was last updated
  }

  struct Nft {
    uint xp;
    int  deposit;
    uint withdrawal;
    bool isActive;
    uint lastOwnershipChange; 
  }

  error ReachedMaxSupply               ();
  error SyncTooSoon                    ();
  error DyadTotalSupplyZero            ();
  error ExceedsAverageTVL              ();
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
  error MissingPermission              (uint id, Permission permission);

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
  function hasPermission(uint id, address operator, Permission) external view returns (bool);
  function hasPermissions(uint id, address operator, Permission[] calldata) external view returns (bool[] calldata);
  function idToNftPermission(uint id, address operator) external view returns (NftPermission memory);

  /**
   * @notice Mint a new dNFT
   * @dev Will revert:
   *      - If `msg.value` is not enough to cover the deposit minimum
   *      - If the max supply of dNFTs has been reached
   *      - If `to` is the zero address
   * @dev Emits:
   *      - Minted
   *      - DyadMinted
   * @param to The address to mint the dNFT to
   * @return id Id of the new dNFT
   */
  function mint(address to) external payable returns (uint id);

  /**
   * @notice Mint and deposit new DYAD into dNFT
   * @dev Will revert:
   *      - If dNFT is not owned by `msg.sender`
   *      - If `amount` minted is 0
   * @dev Emits:
   *      - DyadMinted
   * @param id Id of the dNFT
   * @return amount Amount minted
   */
  function exchange(uint id) external payable;

  function deposit   (uint id, uint amount) external;
  function move      (uint from, uint to, int amount) external;
  function withdraw  (uint from, address to, uint amount) external;
  function redeem    (uint from, address to, uint amount) external returns (uint);
  function sync      (uint id) external;
  function claim     (uint id) external returns (int);
  function snipe     (uint from, uint to) external;
  function activate  (uint id) external;
  function deactivate(uint id) external;
  function grant     (uint id, PermissionSet[] calldata) external;

  function MAX_SUPPLY() external pure returns (uint);
  function MINT_MINIMUM() external pure returns (uint);

  // ERC721
  function ownerOf(uint tokenId) external view returns (address);
  function balanceOf(address owner) external view returns (uint256 balance);
  function approve(address spender, uint256 id) external;
  function transferFrom(address from, address to, uint256 id) external;

  // ERC721Enumerable
  function totalSupply() external view returns (uint256);
  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
  function tokenByIndex(uint256 index) external view returns (uint256);
}

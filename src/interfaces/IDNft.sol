// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

enum Permission { ACTIVATE, DEACTIVATE, DEPOSIT, MOVE, WITHDRAW, REDEEM, CLAIM }

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
    uint lastOwnershipChange; 
    bool isActive;
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
  function MAX_SUPPLY()     external view returns (uint);
  function MINT_MINIMUM()   external view returns (uint);
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
   * @notice Exchange ETH for deposited DYAD
   * @dev Will revert:
   *      - If dNFT does not exist
   * @dev Emits:
   *      - Exchanged
   * @dev For Auditors:
   *      - Permissionless by design
   *      - To save gas it does not check if `msg.value` is zero 
   * @param id Id of the dNFT that gets the deposited DYAD
   * @return amount Amount of DYAD deposited
   */
  function exchange(uint id) external payable returns (int);

  /**
   * @notice Deposit `amount` of DYAD back into dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `DEPOSIT` permission
   *      - dNFT is inactive
   *      - `amount` to deposit exceeds the dNFT withdrawals
   * @dev Emits:
   *      - Deposited
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is zero 
   * @param id Id of the dNFT that gets the deposited DYAD
   * @param amount Amount of DYAD to deposit
   * @return amount Amount of DYAD deposited
   */
  function deposit(uint id, uint amount) external returns (uint);

  /**
   * @notice Move `amount` `from` one dNFT deposit `to` another dNFT deposit
   * @dev Will revert:
   *      - `amount` is not greater than zero
   *      - If `msg.sender` is not the owner of the `from` dNFT AND does not have the
   *        `MOVE` permission for the `from` dNFT
   *      - dNFT is inactive
   *      - `amount` to move exceeds the `from` dNFT deposit 
   * @dev Emits:
   *      - Moved
   * @dev For Auditors:
   *      - To save gas it does not check if `from` == `to`
   * @param from Id of the dNFT to move the deposit from
   * @param to Id of the dNFT to move the deposit to
   * @param amount Amount of DYAD to move
   * @return amount Amount of DYAD moved
   */
  function move(uint from, uint to, int amount) external returns (int);

  /**
   * @notice Withdraw `amount` of DYAD from dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `WITHDRAW` permission
   *      - dNFT is inactive
   *      - If DYAD was deposited into the dNFt in the same block. Needed to
   *        prevent flash-loan attacks
   *      - If `amount` to withdraw is larger than the dNFT deposit
   *      - If Collateralization Ratio is is less than the min collaterization 
   *        ratio after the withdrawal
   *      - If dNFT withdrawal is larger than the average TVL after the 
   *        withdrawal
   * @dev Emits:
   *      - Withdrawn
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - To save gas it does not check if `from` == `to`
   * @param from Id of the dNFT to withdraw from
   * @param to Address to send the DYAD to
   * @param amount Amount of DYAD to withdraw
   * @return amount Amount withdrawn
   */
  function withdraw(uint from, address to, uint amount) external returns (uint);

  /**
   * @notice Redeem `amount` of DYAD for ETH
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `REDEEM` permission
   *      - If `amount` is 0
   * @dev Emits:
   *      - DyadRedeemed
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - There is a re-entrancy risk while transfering the ETH, that is why the 
   *        `nonReentrant` modifier is used
   * @param from Id of the dNFT to redeem from
   * @param to Address to send the ETH to
   * @param amount Amount of DYAD to redeem
   * @return eth Amount of ETH redeemed for DYAD
   */
  function redeem(uint from, address to, uint amount) external returns (uint);

  /**
   * @notice Determine amount of dyad to mint/burn in the next claim window
   * @dev Will revert:
   *      - If dNFT with `id` is not active
   *      - If the total supply of dyad is 0
   *      - If the total supply of dyad is 0
   *      - Is called to soon after last sync as determined by `MIN_TIME_BETWEEN_SYNC`
   *      - The price between the last sync and now is too small as determined by `MIN_PRICE_CHANGE_BETWEEN_SYNC`
   * @dev Emits:
   *      - Synced
   * @dev For Auditors:
   *      - No need to check if the dNFT exists because a dNFT that does not exist is inactive
   * @param id Id of the dNFT that gets a boost
   * @return dyadDelta Amount of dyad to mint/burn
   */
  function sync(uint id) external returns (int);

  /**
   * @notice Claim DYAD from the current sync window
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `CLAIM` permission
   *      - If dNFT is inactive
   *      - If `claim` was already called for that dNFT in this sync window
   * @dev Emits:
   *      - Claimed
   * @param id Id of the dNFT that gets claimed for
   * @return share Amount of DYAD claimed
   */
  function claim(uint id) external returns (int);

  /**
   * @notice Snipe DYAD from previouse sync window to get a bonus
   * @dev Will revert:
   *      - If `from` dNFT is inactive
   *      - If `to` dNFT is inactive
   *      - If `snipe` was already called for that dNFT in this sync window
   * @dev Emits:
   *      - Sniped
   * @param from Id of the dNFT that gets sniped
   * @param to Id of the dNFT that gets the snipe reward
   * @return share Amount of DYAD sniped
   */
  function snipe(uint from, uint to) external returns (int);

  /**
   * @notice Liquidate dNFT by covering its deposit and transfering it to a new owner
   * @dev Will revert:
   *      - If dNFT deposit is not negative
   *      - If ETH sent is not enough to cover the negative dNFT deposit
   * @dev Emits:
   *      - Liquidated
   * @dev For Auditors:
   *      - No need to check if the dNFT exists because a dNFT that does not exist
   *        can not have a negative deposit
   *      - We can calculate the absolute deposit value by multiplying with -1 because it
   *        is always negative
   *      - The `_burn` + `_mint` pattern allows the contract to transfer the dNFT
   *        to a new owner without being approved for it
   *      - No need to delete `idToNft`, because its data is kept as it is or overwritten
   *      - All permissions for this dNFT are reset because `_mint` calls `_beforeTokenTransfer`
   *        which updates the `lastOwnershipChange`
   * @param id Id of the dNFT to liquidate
   * @param to Address to send the dNFT to
   */
  function liquidate(uint id, address to) external payable;

  /**
   * @notice Activate dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `ACTIVATE` permission
   *      - dNFT is active already
   * @dev Emits:
   *      - Activated
   * @param id Id of the dNFT to activate
   */
  function activate(uint id) external;

  /**
   * @notice Deactivate dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `DEACTIVATE` permission
   *      - dNFT is inactive already
   *      - dNFT withdrawal is larger than 0
   *      - dNFT deposit is negative
   * @dev Emits:
   *      - Deactivated
   * @param id Id of the dNFT to deactivate
   */
  function deactivate(uint id) external;

  /**
   * @notice Grant and/or revoke permissions
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT  
   * @dev Emits:
   *      - Modified
   * @dev To remove all permissions for a specific operator pass in an empty Permission array
   *      for that PermissionSet
   * @param id Id of the dNFT's permissions to modify
   * @param permissionSets Permissions to grant and revoke fro specific operators
   */
  function grant(uint id, PermissionSet[] calldata permissionSets) external;


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

// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

enum Permission { ACTIVATE, DEACTIVATE, EXCHANGE, DEPOSIT, MOVE, WITHDRAW, REDEEM, CLAIM }

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

  // view functions
  function MAX_SUPPLY()     external view returns (uint);
  function XP_MINT_REWARD() external view returns (uint);
  function XP_SYNC_REWARD() external view returns (uint);
  function maxXp()          external view returns (uint);
  function idToNft(uint id) external view returns (Nft memory);
  function dyadDelta()      external view returns (int);
  function prevDyadDelta()  external view returns (int);
  function totalXp()        external view returns (uint);
  function syncedBlock()    external view returns (uint);
  function prevSyncedBlock()external view returns (uint);
  function ethPrice()       external view returns (uint);
  function totalDeposit()   external view returns (int);
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
   * @notice Exchange ETH for DYAD deposit
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `EXCHANGE` permission
   *      - dNFT is inactive
   * @dev Emits:
   *      - Exchanged
   * @dev For Auditors:
   *      - To save gas it does not check if `msg.value` is zero 
   * @param id Id of the dNFT that gets the deposited DYAD
   * @return amount Amount of DYAD deposited
   */
  function exchange(uint id) external payable returns (int);

  /**
   * @notice Deposit `amount` of DYAD ERC-20 tokens into the dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `DEPOSIT` permission
   *      - dNFT is inactive
   *      - `amount` to deposit exceeds the dNFT withdrawals
   *      - if `msg.sender` does not have a DYAD balance of at least `amount`
   * @dev Emits:
   *      - Deposited
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is zero 
   *      - `dyad.burn` is called in the beginning so we can revert as fast as
   *        possible if `msg.sender` does not have enough DYAD. The dyad contract
   *        is truested so it introduces no re-entrancy risk.
   * @param id Id of the dNFT that gets the deposited DYAD
   * @param amount Amount of DYAD to deposit
   */
  function deposit(uint id, uint amount) external;

  /**
   * @notice Move `amount` `from` one dNFT deposit `to` another dNFT deposit
   * @dev Will revert:
   *      - `amount` is not greater than zero
   *      - If `msg.sender` is not the owner of the `from` dNFT AND does not have the
   *        `MOVE` permission for the `from` dNFT
   *      - `amount` to move exceeds the `from` dNFT deposit 
   * @dev Emits:
   *      - Moved(uint indexed from, uint indexed to, int amount)
   * @dev For Auditors:
   *      - `amount` is int not uint because it saves us a lot of gas in doing
   *        the int to uint conversion. But thats means we have to put in the 
   *        `require(_amount > 0)` check.
   *      - To save gas it does not check if `from` == `to`, which is not a 
   *        problem because `move` is symmetrical.
   * @param from Id of the dNFT to move the deposit from
   * @param to Id of the dNFT to move the deposit to
   * @param amount Amount of DYAD to move
   */
  function move(uint from, uint to, int amount) external;

  /**
   * @notice Withdraw `amount` of deposited DYAD as an ERC-20 token from a dNFT
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
   *      - Withdrawn(uint indexed from, address indexed to, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - To prevent flash-loan attacks, (`exchange` or `deposit`) and 
   *        `withdraw` can not be called for the same dNFT in the same block
   * @param from Id of the dNFT to withdraw from
   * @param to Address to send the DYAD to
   * @param amount Amount of DYAD to withdraw
   * @return collatRatio New Collateralization Ratio after the withdrawal
   */
  function withdraw(uint from, address to, uint amount) external returns (uint);

  /**
   * @notice Redeem `amount` of DYAD for ETH
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `REDEEM` permission
   *      - If dNFT is inactive
   *      - If DYAD to redeem is larger than the dNFT withdrawal
   *      - If the ETH transfer fails
   * @dev Emits:
   *      - Redeemed(uint indexed from, address indexed to, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - `dyad.burn` is called in the beginning so we can revert as fast as
   *        possible if `msg.sender` does not have enough DYAD. The dyad contract
   *        is trusted so it introduces no re-entrancy risk.
   *      - There is a re-entrancy risk while transfering the ETH, that is why the 
   *        `nonReentrant` modifier is used and all state changes are done before
   *         the ETH transfer
   *      - We do not restrict the amount of gas that can be consumed by the ETH
   *        transfer. This is intentional, as the user calling this function can
   *        always decide who should get the funds. 
   * @param from Id of the dNFT to redeem from
   * @param to Address to send the ETH to
   * @param amount Amount of DYAD to redeem
   * @return eth Amount of ETH redeemed for DYAD
   */
  function redeem(uint from, address to, uint amount) external returns (uint);

  /**
   * @notice Determine amount of claimable DYAD 
   * @dev Will revert:
   *      - If dNFT with `id` is not active
   *      - If the total supply of DYAD is 0
   *      - Is called to soon after last sync as determined by `MIN_TIME_BETWEEN_SYNC`
   *      - If the new ETH price is the same as the one from the previous sync
   * @dev Emits:
   *      - Synced(uint id)
   * @dev For Auditors:
   *      - No need to check if the dNFT exists because a dNFT that does not exist
   *        is inactive
   *      - Amount to mint/burn is based only on withdrawn DYAD
   *      - The chainlink update threshold is currently set to 50 bps
   * @param id Id of the dNFT that gets a boost
   * @return dyadDelta Amount of claimable DYAD
   */
  function sync(uint id) external returns (int);

  /**
   * @notice Claim DYAD from the current sync window
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `CLAIM` permission
   *      - If dNFT is inactive
   *      - If `claim` was already called for that dNFT in this sync window
   *      - If dNFT deposit is negative
   *      - If DYAD will be burned and `totalDeposit` is negative
   * @dev Emits:
   *      - Claimed
   * @dev For Auditors:
   *      - `timeOfLastSync` is not set deliberately in the constructor. `sync`
   *        should be callable as fast as possible after deployment.
   * @param id Id of the dNFT that gets claimed for
   * @return share Amount of DYAD claimed
   */
  function claim(uint id) external returns (int);

  /**
   * @notice Snipe unclaimed DYAD from someone else
   * @dev Will revert:
   *      - If `from` dNFT is inactive
   *      - If `to` dNFT is inactive
   *      - If `from` equals `to`
   *      - If `snipe` was already called for that dNFT in this sync window
   *      - If dNFT deposit is negative
   *      - If DYAD will be burned and `totalDeposit` is negative
   * @dev Emits:
   *      - Sniped
   * @param from Id of the dNFT that gets sniped
   * @param to Id of the dNFT that gets the snipe reward
   * @return share Amount of DYAD sniped
   */
  function snipe(uint from, uint to) external returns (int);

  /**
   * @notice Liquidate dNFT by covering its negative deposit and transfering it 
   *         to a new owner
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
   *      - No need to delete `idToNft`, because its data is kept as it is or overwritten
   *      - All permissions for this dNFT are reset because `_transfer` calls `_beforeTokenTransfer`
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

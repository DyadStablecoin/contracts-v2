// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IClaimer {

  struct Config {
    int  fee;          // fee collected for every claim. for example 0.1e18 = 10%
    uint feeCollector; // dNFT that gets the fee
    uint maxClaimers;  // maximum number of dNfts that can be claimed for
  }

  event ConfigSet (Config _config);
  event Added     (uint indexed id);
  event Removed   (uint indexed id);
  event ClaimedAll();

  error InvalidFee        ();
  error TooManyClaimers   ();
  error MissingPermissions();
  error NotNFTOwner       ();
  error IdAlreadyInSet    ();
  error IdNotInSet        ();

  /**
   * @notice Set the config
   * @dev Will revert:
   *      - If it is not called by the owner
   *      - If the new fee is higher than the max fee as specified by `MAX_FEE`
   * @dev Emits:
   *      - ConfigSet(Config config)
   * @param config The new config that will replace the current config
   */
  function setConfig(Config memory config) external;

  /**
   * @notice Add dNFT to set of Claimers
   * @dev Will revert:
   *      - If it is not called by the owner of the dNFT
   *      - If the dNFT is already in the set of Claimers
   *      - If the max number of claimers is reached
   *      - If the dNFT is missing the required permissions
   * @dev Emits:
   *      - Added(uint id)
   * @param id The id of the dNFT to add
   */
  function add(uint id) external;

  /**
   * @notice Remove dNFT from set of Claimers
   * @dev Will revert:
   *      - If it is not called by the owner of the dNFT
   *      - If the dNFT is not in the set of Claimers
   * @dev Emits:
   *      - Removed(uint id)
   * @param id The id of the dNFT to remove
   */
  function remove(uint id) external;

  /**
   * @notice Claim for all dNFTs in the Claimers set
   * @dev Emits:
   *      - ClaimedAll()
   * @dev Note: The dNFT will be removed from the set of claimers if the `claim`
   *      or `move` function reverts for it
   */
  function claimAll() external;

  /**
   * @notice Check if the dNFT id is in the set of Claimers
   * @param id The id of the dNFT to check for
   * @return True if the dNFT is in the set of Claimers, false otherwise
   */
  function contains(uint id) external returns (bool);

  /**
   * @notice Get the number of dNFTs in the set of Claimers
   * @return The number of dNFTs in the set of Claimers
   */
  function length() external returns (uint);
}

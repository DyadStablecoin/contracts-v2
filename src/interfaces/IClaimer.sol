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

  error InvalidFee        (int fee);
  error InvalidMaxClaimers(uint maxClaimers);
  error TooManyClaimers   ();
  error MissingPermissions();
  error NotNFTOwner       (uint id);

  /**
   * @notice Set the config
   * @dev Will revert:
   *      - If it is not called by the owner
   *      - If the new fee is higher than the max fee as specified by `MAX_FEE`
   *      - If the new max claimers is lower than the current max claimers
   * @dev Emits:
   *      - ConfigSet(Config config)
   * @param config The new config that will replace the current config
   */
  function setConfig(Config memory config) external;

  /**
   * @notice Add dNFT to set of Claimers
   * @dev Will revert:
   *      - If it is not called by the owner of the dNFT
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
   *      or `move` function reverts
   */
  function claimAll() external;
}

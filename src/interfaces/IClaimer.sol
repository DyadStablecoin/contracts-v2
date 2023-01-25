// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IClaimer {

  struct Config {
    int  fee;          // fee collected for every claim. for example 0.1e18 = 10%
    uint feeCollector; // dNFT that gets the fee
    uint maxClaimers;  // maximum number of dNfts that can be claimed for
  }

  event ConfigSet (Config _config);
  event Added     (uint id);
  event Removed   (uint id);
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
   * @notice Add dNFT to the claim list
   * @dev Will revert:
   *      - If it is not called by the owner of the dNFT
   *      - If the max number of claimers is reached
   *      - If the dNFT does not have the required permissions
   * @dev Emits:
   *      - Added(uint id)
   * @param id The id of the dNFT to add
   */
  function add(uint id) external;

  /**
   * @notice Remove dNFT from the claim list
   * @dev Will revert:
   *      - If it is not called by the owner of the dNFT
   * @dev Emits:
   *      - Removed(uint id)
   * @param id The id of the dNFT to add
   */
  function remove(uint id) external;

  /**
   * @notice Call claim for all dNFTs on the claim list
   * @dev Emits:
   *      - ClaimedAll()
   * @dev Note: If calling the claim function for a dNFT fails for 
   *      any reason, it will be removed from the claim list
   */
  function claimAll() external;
}

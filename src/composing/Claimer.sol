// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IDNft, Permission} from "../interfaces/IDNft.sol";

// Stake your dNFT to automatically get `claim` called for you
contract Claimer is Owned {
  using EnumerableSet for EnumerableSet.UintSet;

  int public constant MAX_FEE = 0.1e18; // 1000 bps or 10%

  EnumerableSet.UintSet private dNfts;

  struct Config {
    int  fee;
    uint feeCollector; // dNFT that gets the fee
    uint maxClaimers;  // maximum number of dNfts that can be claimed for
  }

  IDNft  public dNft;
  Config public config;

  error InvalidFee        (int fee);
  error InvalidMaxClaimers(uint maxClaimers);
  error TooManyClaimers   ();
  error MissingPermissions();
  error NotNFTOwner       (uint id);

  modifier onlyNftOwner(uint id) {
    require(dNft.ownerOf(id) == msg.sender);
    _;
  }

  constructor(IDNft _dnft, Config memory _config) Owned(msg.sender) {
    dNft   = _dnft;
    config = _config;
  }

  function setConfig(Config memory _config) external onlyOwner {
    if (_config.fee <= MAX_FEE) revert InvalidFee(_config.fee);
    if (_config.maxClaimers <= config.maxClaimers) revert InvalidMaxClaimers(_config.maxClaimers);
    config = _config;
  }

  function hasPermission(uint id) public view returns (bool) {
    Permission[] memory reqPermissions = new Permission[](2);
    reqPermissions[0] = Permission.CLAIM;
    reqPermissions[1] = Permission.MOVE;
    bool[] memory permissions = dNft.hasPermissions(id, address(this), reqPermissions);
    return (permissions[0] && permissions[1]);
  }

  // add DNft to claim list
  function add(uint id) external onlyNftOwner(id) { 
    if (dNft.balanceOf(address(this)) >= config.maxClaimers) revert TooManyClaimers();
    if (!hasPermission(id)) revert MissingPermissions();
    dNfts.add(id);
  }

  // remove DNft from claim list
  function remove(uint id) external onlyNftOwner(id) {
    dNfts.remove(id);
  }

  // claim for all DNfts
  function claimAll() external {
    uint[] memory ids = dNfts.values();
    for (uint i = 0; i < ids.length; ) {
      uint id = ids[i];
      // will fail if this contract does not have the required permissions
      try dNft.claim(id) returns (int share) { 
        // a fee is only collected if dyad is added to the dNft deposit
        if (share > 0) {
          int fee = wadMul(share, config.fee);
          if (fee > 0) { dNft.move(id, config.feeCollector, fee); }
        }
      } catch {
        dNfts.remove(id);
      }
      unchecked { ++i; }
    }
  }
}

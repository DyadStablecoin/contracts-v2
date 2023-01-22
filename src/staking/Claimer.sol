// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;
import "forge-std/console.sol";

import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IDNft, Permission} from "../interfaces/IDNft.sol";

// Stake your dNFT to automatically get `claim` called for you
contract Claimer is Owned {
  using EnumerableSet for EnumerableSet.UintSet;

  int public constant MAX_FEE = 0.1e18; // 1000 bps or 10%

  mapping(uint => address) public owners;
  EnumerableSet.UintSet private dNfts;

  struct Config {
    int  fee;
    uint feeCollector; // dNFT that gets the fee
    uint maxClaimers;
  }

  IDNft  public dNft;
  Config public config;

  error InvalidFee        (int fee);
  error InvalidMaxClaimers(uint maxClaimers);
  error NotStakeOwner     (address sender, uint id);
  error TooManyClaimers   ();
  error MissingPermissions();
  error NotNFTOwner       (uint id);

  modifier onlyStakeOwner(uint id) {
    if (owners[id] != msg.sender) revert NotStakeOwner(msg.sender, id);
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

  // Stake dNFT
  function add(uint id) external { // will fail if dNFT does not exist
    if (dNft.balanceOf(address(this)) >= config.maxClaimers) revert TooManyClaimers();
    if (!hasPermission(id)) revert MissingPermissions();
    dNfts.add(id);
  }

  // Unstake dNFT
  function remove(uint id) external {
    if (dNft.ownerOf(id) != address(this)) revert NotNFTOwner(id);
    dNfts.remove(id);
  }

  // Claim for all staked dNFTs
  function claimAll() external {
    uint numberOfStakedNfts = dNft.balanceOf(address(this)); // save gas
    for (uint i = 0; i < numberOfStakedNfts; ) { 
      uint id    = dNft.tokenOfOwnerByIndex(address(this), i);
      int  share = dNft.claim(id);
      // can not revert, because we are moving share of a deposit that was just claimed
      if (share > 0) {
        int fee = wadMul(share, config.fee);
        if (fee > 0) { dNft.move(id, config.feeCollector, fee); }
      }
      unchecked { ++i; }
    }
  }
}

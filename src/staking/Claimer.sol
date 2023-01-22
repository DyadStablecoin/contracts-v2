// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;
import "forge-std/console.sol";

import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";
import {IDNft, Permission} from "../interfaces/IDNft.sol";

// Stake your dNFT to automatically get `claim` called for you
contract Claimer is Owned {
  int public constant MAX_FEE = 0.1e18; // 1000 bps or 10%

  mapping(uint => address) public owners;

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
  error ClaimPermissionRequired();
  error MovePermissionRequired ();

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

  // Stake dNFT
  function stake(uint id) external { // will fail if dNFT does not exist
    if (dNft.balanceOf(address(this)) >= config.maxClaimers) revert TooManyClaimers();
    Permission[] memory reqPermissions = new Permission[](2);
    reqPermissions[0] = Permission.CLAIM;
    reqPermissions[1] = Permission.MOVE;
    bool[] memory permissions = dNft.hasPermissions(id, address(this), reqPermissions);
    if (!permissions[0]) { revert ClaimPermissionRequired(); }
    if (!permissions[1]) { revert MovePermissionRequired(); }
    owners[id] = msg.sender;
    dNft.transferFrom(msg.sender, address(this), id);
  }

  // Unstake dNFT
  function unstake(uint id) external onlyStakeOwner(id) {
    delete owners[id];
    dNft.transferFrom(address(this), msg.sender, id);
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

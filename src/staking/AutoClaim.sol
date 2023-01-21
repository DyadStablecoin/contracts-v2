// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;
import "forge-std/console.sol";

import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";
import {DNft} from "../core/DNft.sol";

contract AutoClaim is Owned {
  int public constant MAX_FEE = 0.1e18;    // 1000 bps or 10%
  int public constant MIN_FEE = 0.0001e18; // 1    bps or 0.01%

  mapping(uint => address) public owners;

  struct Params {
    int  fee;
    uint feeCollector;
    uint maxStaker;
  }

  DNft public dNft;
  Params public params;

  modifier onlyStakeOwner(uint id) {
    require(owners[id] == msg.sender, "AutoClaim: not owner");
    _;
  }

  constructor(DNft _dnft, Params memory _params) Owned(msg.sender) {
    dNft       = _dnft;
    params     = _params;
  }

  function setParams(Params memory _params) external onlyOwner {
    require(_params.fee >= MIN_FEE && _params.fee <= MAX_FEE);
    params = _params;
  }

  // Stake dNFT
  function stake(uint id) external { // will fail if dNFT does not exist
    require(dNft.balanceOf(address(this)) < params.maxStaker);
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
    uint numberOfStakedNfts = dNft.balanceOf(address(this));
    for (uint i = 0; i < numberOfStakedNfts; ) { 
      uint id    = dNft.tokenOfOwnerByIndex(address(this), i);
      int  share = dNft.claim(id);
      if (share > 0) { dNft.move(id, params.feeCollector, wadMul(share, params.fee)); }
      unchecked { ++i; }
    }
  }
}

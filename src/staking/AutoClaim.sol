// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {DNft} from "../core/DNft.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

contract AutoClaim is Owned {

  uint constant MAX_STAKER = 100;
  uint public masterDNft;
  DNft public dNft;
  mapping(uint => address) public owners;

  modifier onlyStakeOwner(uint id) {
    require(owners[id] == msg.sender, "AutoClaim: not owner");
    _;
  }

  constructor (DNft _dnft, uint _masterDNft) Owned(msg.sender) {
    dNft       = _dnft;
    masterDNft = _masterDNft;
  }

  function setMasterDNft(uint _masterDNft) external onlyOwner {
    masterDNft = _masterDNft;
  }

  function stake() external {
    require(dNft.balanceOf(address(this)) < MAX_STAKER);
  }

  function unstake(uint id) external onlyStakeOwner(id) {}

  function claimAll() external {
    uint numberOfStakedNfts = dNft.balanceOf(address(this));
    for (uint i = 0; i < numberOfStakedNfts; i++) { // iterate over all staked dNfts
      uint id   = dNft.tokenOfOwnerByIndex(address(this), i);
      int share = dNft.claim(id);
      if (share > 0) {
        dNft.move(id, masterDNft, 100);
      }
    }
  }
}

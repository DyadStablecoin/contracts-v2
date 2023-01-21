// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {DNft} from "../core/DNft.sol";

contract AutoClaim {

  DNft public dNft;
  mapping(address => uint)  public owner;

  constructor (DNft _dnft) {
    dNft = _dnft;
  }

  function stake() external {}

  function unstake() external {}

  function claim() external {


  }
}

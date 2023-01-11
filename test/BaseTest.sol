// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {DNfts} from "../src/core/DNfts.sol";

contract BaseTest is Test {
  DNfts dNfts;

  function setUp() public {
    DeployBase deployBase = new DeployBase();
    (address _dNfts, ) = deployBase.deploy();
    dNfts = DNfts(_dNfts);
  }

}

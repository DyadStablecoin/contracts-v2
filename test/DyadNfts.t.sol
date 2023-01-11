// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {DyadNfts} from "../src/core/DyadNfts.sol";

contract DyadNftsTest is Test {
  DyadNfts dyadNfts;

  function setUp() public {
    DeployBase deployBase = new DeployBase();
    (address _dyadNfts, ) = deployBase.deploy();
    dyadNfts = DyadNfts(_dyadNfts);
  }

}

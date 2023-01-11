// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {IDyadNfts} from "../src/interfaces/IDyadNfts.sol";

contract BaseTest is Test {
  IDyadNfts dyadNfts;

  function setUp() public {
    DeployBase deployBase = new DeployBase();
    (address _dyadNfts, ) = deployBase.deploy();
    dyadNfts = IDyadNfts(_dyadNfts);
  }

}

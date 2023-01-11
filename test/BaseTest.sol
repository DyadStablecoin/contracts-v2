// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {DNft} from "../src/core/DNft.sol";

contract BaseTest is Test {
  DNft dNfts;

  function setUp() public {
    DeployBase deployBase = new DeployBase();
    (address _dNfts, ) = deployBase.deploy();
    dNfts = DNft(_dNfts);
  }

}

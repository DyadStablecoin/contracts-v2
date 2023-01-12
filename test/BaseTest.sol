// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract BaseTest is Test {
  IDNft dNft;

  function setUp() public {
    DeployBase deployBase = new DeployBase();
    (address _dNfts, ) = deployBase.deploy();
    dNft = IDNft(_dNfts);
  }

}

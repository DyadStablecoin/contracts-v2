// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";

contract DyadNftsTest is BaseTest, Parameters {
  function testInsiderAllocation() public {
    assertEq(dyadNfts.totalSupply(), INSIDERS.length);

    assertEq(dyadNfts.balanceOf(INSIDERS[0]), 1);
    assertEq(dyadNfts.balanceOf(INSIDERS[1]), 1);
    assertEq(dyadNfts.balanceOf(INSIDERS[2]), 1);

    assertEq(dyadNfts.ownerOf(0), INSIDERS[0]);
    assertEq(dyadNfts.ownerOf(1), INSIDERS[1]);
    assertEq(dyadNfts.ownerOf(2), INSIDERS[2]);
  }
}

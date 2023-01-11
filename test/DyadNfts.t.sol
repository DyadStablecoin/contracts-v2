// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {BaseTest} from "./BaseTest.sol";

contract DyadNftsTest is BaseTest {
  function testBla() public {
    dyadNfts.ownerOf(0);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";

contract DyadNftsTest is BaseTest, Parameters {
  function testInsiderAllocation() public {
    assertEq(dNfts.totalSupply(), INSIDERS.length);

    assertEq(dNfts.balanceOf(INSIDERS[0]), 1);
    assertEq(dNfts.balanceOf(INSIDERS[1]), 1);
    assertEq(dNfts.balanceOf(INSIDERS[2]), 1);

    assertEq(dNfts.ownerOf(0), INSIDERS[0]);
    assertEq(dNfts.ownerOf(1), INSIDERS[1]);
    assertEq(dNfts.ownerOf(2), INSIDERS[2]);
  }

  function testInsiderXpAllocation() public {
    (uint xp,,,) = dNfts.idToNft(0);
    assertEq(xp, dNfts.MAX_SUPPLY()*2);

    (xp,,,) = dNfts.idToNft(1);
    assertEq(xp, dNfts.MAX_SUPPLY()*2-1);
  }
}

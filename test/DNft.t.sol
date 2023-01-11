// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract DNftsTest is BaseTest, Parameters {
  function testInsidersAllocation() public {
    assertEq(dNfts.totalSupply(), INSIDERS.length);

    assertEq(dNfts.balanceOf(INSIDERS[0]), 1);
    assertEq(dNfts.balanceOf(INSIDERS[1]), 1);
    assertEq(dNfts.balanceOf(INSIDERS[2]), 1);

    assertEq(dNfts.ownerOf(0), INSIDERS[0]);
    assertEq(dNfts.ownerOf(1), INSIDERS[1]);
    assertEq(dNfts.ownerOf(2), INSIDERS[2]);
  }

  function testInsidersXpAllocation() public {
    assertEq(dNfts.idToNft(0).xp, dNfts.maxSupply()*2);
    assertEq(dNfts.idToNft(1).xp, dNfts.maxSupply()*2-1);
    assertEq(dNfts.idToNft(2).xp, dNfts.maxSupply()*2-2);
  }
}

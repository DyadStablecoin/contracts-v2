// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract E2ETest is BaseTest, Parameters {
  function testMint() public {

    console.log(dNft.idToNft(0).xp);
    overwriteNft(0, 100, 200, 400);
    console.log(dNft.idToNft(0).xp);
  }
}


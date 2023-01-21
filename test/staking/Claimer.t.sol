// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "../BaseTest.sol";
import {Parameters} from "../../src/Parameters.sol";
import {IDNft} from "../../src/interfaces/IDNft.sol";

contract AutoClaim is BaseTest, Parameters {

  function testStake() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.approve(address(claimer), id);
    claimer.stake(id);
  }

  function testUnstake() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.approve(address(claimer), id);
    claimer.stake(id);
    // unstake and stake again
    claimer.unstake(id);
    dNft.approve(address(claimer), id);
    claimer.stake(id);
  }

  function testClaimAll() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.approve(address(claimer), id);
    claimer.stake(id);

    overwrite(address(dNft), "dyadDelta()", 100*1e18);

    int masterDepositBefore = dNft.idToNft(0).deposit;
    claimer.claimAll();
    assertTrue(dNft.idToNft(0).deposit > masterDepositBefore);
  }
}

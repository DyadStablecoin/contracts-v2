// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "../BaseTest.sol";
import {IDNft, Permission, PermissionSet} from "../../src/interfaces/IDNft.sol";

contract ClaimerTest is BaseTest {

  function _givePermission(uint id) internal {
    Permission[] memory pp = new Permission[](2);
    pp[0] = Permission.CLAIM;
    pp[1] = Permission.MOVE;

    PermissionSet[] memory ps = new PermissionSet[](1);
    ps[0] = PermissionSet(address(claimer), pp);

    dNft.grant(id, ps);
  }

  function testAdd() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));

    _givePermission(id);
    claimer.add(id);
  }

  function testRemove() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.approve(address(claimer), id);
    _givePermission(id);
    claimer.add(id);
    // remove and add again
    claimer.remove(id);
    claimer.add(id);
  }

  function testClaimAll() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    _givePermission(id);
    claimer.add(id);

    overwrite(address(dNft), "dyadDelta()", 100*1e18);

    int masterDepositBefore = dNft.idToNft(0).deposit;
    claimer.claimAll();
    assertTrue(dNft.idToNft(0).deposit > masterDepositBefore);
  }
}


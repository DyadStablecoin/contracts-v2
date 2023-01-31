// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "../BaseTest.sol";
import {IDNft, Permission, PermissionSet} from "../../src/interfaces/IDNft.sol";
import {IClaimer} from "../../src/interfaces/IClaimer.sol";

contract ClaimerTest is BaseTest {

  function _givePermission(uint id) internal {
    Permission[] memory pp = new Permission[](2);
    pp[0] =Permission.CLAIM;
    pp[1] =Permission.MOVE;

    PermissionSet[] memory ps = new PermissionSet[](1);
    ps[0] = PermissionSet(address(claimer), pp);

    dNft.grant(id, ps);
  }

  // -------------------- add --------------------
  function testAdd() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    _givePermission(id);
    claimer.add(id);
    assertTrue(claimer.contains(id));
  }
  function testCannotAddIsNotdNFTOwner() public {
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotNFTOwner.selector));
    claimer.add(0);
  }
  function testCannotAddMaxNumberOfClaimersReached() public {
    for (uint i = 0; i < MAX_NUMBER_OF_CLAIMERS; i++) {
      uint id = dNft.mint{value: 5 ether}(address(this));
      _givePermission(id);
      claimer.add(id);
    }
    uint id2 = dNft.mint{value: 5 ether}(address(this));
    _givePermission(id2);
    vm.expectRevert(abi.encodeWithSelector(IClaimer.TooManyClaimers.selector));
    claimer.add(id2);
  }
  function testCannotAddMissingPermission() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IClaimer.MissingPermissions.selector));
    claimer.add(id);
  }
  function testCannotAdddNFTTwice() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    _givePermission(id);
    claimer.add(id);
    vm.expectRevert(abi.encodeWithSelector(IClaimer.IdAlreadyInSet.selector));
    claimer.add(id);
  }

  // -------------------- remove --------------------
  function testRemove() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    _givePermission(id);
    claimer.add(id);
    // remove and add again
    claimer.remove(id);
    assertTrue(!claimer.contains(id));
    claimer.add(id);
    assertTrue(claimer.contains(id));
  }
  function testCannotRemoveIsNotdNFTOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.prank(address(1));
    _givePermission(id);
    vm.prank(address(1));
    claimer.add(id);

    vm.expectRevert(abi.encodeWithSelector(IDNft.NotNFTOwner.selector));
    claimer.remove(id);
  }
  function testCannotRemovedNFTNotInSetOfClaimers() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IClaimer.IdNotInSet.selector));
    claimer.remove(id);
  }

  // -------------------- claimAll --------------------
  function testClaimAllMint() public {
    // so we have something to claim
    overwrite(address(dNft), "dyadDelta()", 100*1e18);

    for (uint i = 0; i < MAX_NUMBER_OF_CLAIMERS; i++) {
      uint id = dNft.mint{value: 5 ether}(address(this));
      _givePermission(id);
      claimer.add(id);
    }

    (, uint feeCollector,) = claimer.config();

    int feesBefore = dNft.idToNft(feeCollector).deposit;
    int masterDepositBefore0  = dNft.idToNft(0).deposit;
    int masterDepositBefore30 = dNft.idToNft(30).deposit;
    claimer.claimAll();
    assertTrue(feesBefore < dNft.idToNft(feeCollector).deposit);
    assertTrue(dNft.idToNft(0).deposit  > masterDepositBefore0);
    assertTrue(dNft.idToNft(30).deposit > masterDepositBefore30);
  }
}

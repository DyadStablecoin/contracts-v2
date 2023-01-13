// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract DNftsTest is BaseTest, Parameters {
  function testInsidersAllocation() public {
    assertEq(dNft.totalSupply(), INSIDERS.length);

    assertEq(dNft.balanceOf(INSIDERS[0]), 1);
    assertEq(dNft.balanceOf(INSIDERS[1]), 1);
    assertEq(dNft.balanceOf(INSIDERS[2]), 1);

    assertEq(dNft.ownerOf(0), INSIDERS[0]);
    assertEq(dNft.ownerOf(1), INSIDERS[1]);
    assertEq(dNft.ownerOf(2), INSIDERS[2]);
  }

  // -------------------- mint --------------------
  function testMintNft() public {
    dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.totalSupply(), INSIDERS.length + 1);
  }
  function testFailMintToZeroAddress() public {
    dNft.mint(address(0));
  }
  function testCannotMintNotReachedMinAmount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IDNft.NotReachedMinAmount.selector,
        1385100000000000000000
      )
    );
    dNft.mint{value: 1 ether}(address(this));
  }
  function testCannotMintExceedsMaxSupply() public {
    uint nftsLeft = dNft.MAX_SUPPLY() - dNft.totalSupply();
    for (uint i = 0; i < nftsLeft; i++) {
      dNft.mint{value: 5 ether}(address(this));
    }
    assertEq(dNft.totalSupply(), dNft.MAX_SUPPLY());
    vm.expectRevert(abi.encodeWithSelector(IDNft.ReachedMaxSupply.selector));
    dNft.mint{value: 5 ether}(address(this));
  }

  // -------------------- deposit --------------------
  function testDeposit() public {
    uint depositBefore = dNft.idToNft(0).deposit;
    dNft.deposit{value: 5 ether}(0);
    uint depositAfter = dNft.idToNft(0).deposit;
    assertTrue(depositAfter > depositBefore);
  }
  function testCannotDepositDNftDoesNotExist() public {
    uint id = dNft.totalSupply();
    vm.expectRevert(abi.encodeWithSelector(IDNft.DNftDoesNotExist.selector, id));
    dNft.deposit{value: 5 ether}(id);
  }

  // -------------------- move --------------------
  function testMoveDeposit() public {
    uint from = dNft.totalSupply();
    uint to   = 0;
    dNft.mint{value: 5 ether}(address(this));

    uint depositFromBefore = dNft.idToNft(from).deposit;
    uint depositToBefore   = dNft.idToNft(to).deposit;

    dNft.move(from, to, 10000);

    uint depositFromAfter = dNft.idToNft(from).deposit;
    uint depositToAfter = dNft.idToNft(to).deposit;

    assertTrue(depositFromAfter < depositFromBefore);
    assertTrue(depositToAfter   > depositToBefore);
  }
  function testFailMoveDepositNotDNftOwner() public {
    dNft.move(0, 2, 10000); // DNft 0 is owned by one of the insiders
  }
  function testFailMoveDepositCannotMoveDepositToSelf() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.move(id, id, 10000);
  }
  function testFailMoveDepositExceedsDepositBalance() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.move(id, 0, 50000 ether);
  }

  // -------------------- withdraw --------------------
  function testWithdraw() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, 10000);
  }

  // -------------------- redeem --------------------
  function testRedeem() public {
    uint AMOUNT_TO_REDEEM = 10000;
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, AMOUNT_TO_REDEEM);
    dNft.redeem  (id, AMOUNT_TO_REDEEM);
  }
  function testCannotRedeemNotDNftOwner() public {
    uint AMOUNT_TO_REDEEM = 10000;
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, AMOUNT_TO_REDEEM);
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotNFTOwner.selector, 0));
    dNft.redeem  (0, AMOUNT_TO_REDEEM);
  }

  // -------------------- burn --------------------
  function testBurn() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.burn(id, 10_000);
  }
}

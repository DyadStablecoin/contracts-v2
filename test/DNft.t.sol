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

  // -------------------- mintNft --------------------
  function testMintNft() public {
    dNft.mintNft{value: 5 ether}(address(this));
    assertEq(dNft.totalSupply(), INSIDERS.length + 1);
  }
  function testFailMintToZeroAddress() public {
    dNft.mintNft(address(0));
  }
  function testFailMintNoEthSupplied() public {
    dNft.mintNft(address(this));
  }
  function testFailMintNotReachedMinAmount() public {
    dNft.mintNft{value: 1 ether}(address(this));
  }
  function testFailMintExceedsMaxSupply() public {
    uint nftsLeft = dNft.maxSupply() - dNft.totalSupply();
    for (uint i = 0; i < nftsLeft; i++) {
      dNft.mintNft(address(this));
    }
    assertEq(dNft.totalSupply(), dNft.maxSupply());
    dNft.mintNft(address(this));
  }

  // -------------------- deposit --------------------
  function testDeposit() public {
    uint depositBefore = dNft.idToNft(0).deposit;
    dNft.deposit{value: 5 ether}(0);
    uint depositAfter = dNft.idToNft(0).deposit;
    assertTrue(depositAfter > depositBefore);
  }
  function testFailDepositNoEthSupplied() public {
    dNft.deposit(0);
  }
  function testFailDepositDNftDoesNotExist() public {
    dNft.deposit{value: 5 ether}(dNft.totalSupply());
  }

  // -------------------- deposit --------------------
  function testMoveDeposit() public {
    uint from = dNft.totalSupply();
    uint to   = 0;
    dNft.mintNft{value: 5 ether}(address(this));

    uint depositFromBefore = dNft.idToNft(from).deposit;
    uint depositToBefore   = dNft.idToNft(to).deposit;

    dNft.moveDeposit(from, to, 10000);

    uint depositFromAfter = dNft.idToNft(from).deposit;
    uint depositToAfter = dNft.idToNft(to).deposit;

    assertTrue(depositFromAfter < depositFromBefore);
    assertTrue(depositToAfter   > depositToBefore);
  }
  function testFailMoveDepositNotDNftOwner() public {
    dNft.moveDeposit(0, 2, 10000); // DNft 0 is owned by one of the insiders
  }
  function testFailMoveDepositCannotMoveDepositToSelf() public {
    uint id = dNft.totalSupply();
    dNft.mintNft{value: 5 ether}(address(this));
    dNft.moveDeposit(id, id, 10000);
  }
  function testFailMoveDepositExceedsDepositBalance() public {
    uint id = dNft.totalSupply();
    dNft.mintNft{value: 5 ether}(address(this));
    dNft.moveDeposit(id, 0, 50000 ether);
  }

  // -------------------- withdraw --------------------
  function testWithdraw() public {
    uint id = dNft.totalSupply();
    dNft.mintNft{value: 5 ether}(address(this));
    dNft.withdraw(id, 10000);
  }
}

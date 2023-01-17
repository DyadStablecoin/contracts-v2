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

    assertTrue(dNft.lastEthPrice() > 0); // lastEthPrice is set by oracle
  }
  function testInsidersDeposit() public {
    // all insiders have the same deposit
    assertEq(dNft.idToNft(0).deposit, 10_000*1e18);
    assertEq(dNft.idToNft(1).deposit, 10_000*1e18);
    assertEq(dNft.idToNft(2).deposit, 10_000*1e18);

    // sanity check: dnft that does not exist has no deposit
    assertEq(dNft.idToNft(INSIDERS.length).deposit, 0);
  }

  // -------------------- mint --------------------
  function testMintNft() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.totalSupply(), INSIDERS.length + 1);
    assertEq(dNft.idToNft(id).xp, dNft.XP_MINT_REWARD());
    assertEq(uint(dNft.idToNft(id).deposit), 5 ether / 1e8 * dNft.lastEthPrice());
    assertEq(dNft.idToNft(id).withdrawal, 0);
  }
  function testFailMintToZeroAddress() public {
    dNft.mint{value: 5 ether}(address(0));
  }
  function testCannotMintNotReachedMinAmount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IDNft.UnderDepositMinimum.selector,
        1 ether/1e8 * oracleMock.price()
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

  // -------------------- exchange --------------------
  function testExchange() public {
    int depositBefore = dNft.idToNft(0).deposit;
    dNft.exchange{value: 5 ether}(0);
    int depositAfter = dNft.idToNft(0).deposit;
    assertTrue(depositAfter > depositBefore);
  }
  function testCannotExchangeDNftDoesNotExist() public {
    uint id = dNft.totalSupply();
    vm.expectRevert('NOT_MINTED');
    dNft.exchange{value: 5 ether}(id);
  }

  // -------------------- move --------------------
  function testMoveDeposit() public {
    uint from = dNft.totalSupply();
    uint to   = 0;
    dNft.mint{value: 5 ether}(address(this));

    int depositFromBefore = dNft.idToNft(from).deposit;
    int depositToBefore   = dNft.idToNft(to).deposit;

    dNft.move(from, to, 10000);

    int depositFromAfter = dNft.idToNft(from).deposit;
    int depositToAfter   = dNft.idToNft(to).deposit;

    assertTrue(depositFromAfter < depositFromBefore);
    assertTrue(depositToAfter   > depositToBefore);
  }
  function testCannotMoveDepositNotDNftOwner() public {
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotNFTOwner.selector, 0));
    dNft.move(0, 2, 10000); 
  }
  function testCannotMoveDepositExceedsDepositBalance() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(
      IDNft.ExceedsDepositBalance.selector,
      dNft.idToNft(id).deposit
    ));
    dNft.move(id, 0, 50000000 ether);
  }

  // -------------------- withdraw --------------------
  function testWithdraw() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 2000*1e18);
    dNft.withdraw(id, address(this), 1000*1e18);
  }

  // -------------------- deposit --------------------
  function testDeposit() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 2000*1e18);
    dyad.approve(address(dNft), 2000*1e18);
    dNft.deposit(id, 2000*1e18);
  }

  // -------------------- redeem --------------------
  function testRedeem() public {
    uint AMOUNT_TO_REDEEM = 10000;
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), AMOUNT_TO_REDEEM);
    dNft.redeem  (id, address(this), AMOUNT_TO_REDEEM);
  }
  function testCannotRedeemNotDNftOwner() public {
    uint AMOUNT_TO_REDEEM = 10000;
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), AMOUNT_TO_REDEEM);
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotNFTOwner.selector, 0));
    dNft.redeem  (0, address(this), AMOUNT_TO_REDEEM);
  }

  // -------------------- sync --------------------
  function _sync(uint id, int newPrice) internal {
    dNft.mint{value: 5 ether}(address(this));
    oracleMock.setPrice(newPrice); 
    dNft.sync(id);
  }
  function testSync() public {
    uint totalSupply = dNft.totalSupply();
    uint id          = totalSupply;
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);
    _sync(id, 1001*1e8);

    assertTrue(dNft.dyadDelta() == 1e18);

    // assertTrue(dNft.idToNft(id).xp == 1000*1e18);

    // xp bonus is the mint reward + the full sync reward
    // assertTrue(dNft.idToNft(id).xp == dNft.XP_MINT_REWARD() + dNft.XP_SYNC_REWARD());
    // total xp
    // assertTrue(
    //   dNft.totalXp() == (dNft.XP_MINT_REWARD() * dNft.totalSupply()) + dNft.XP_SYNC_REWARD()
    // );
  }
  function testFailSyncPriceChangeTooSmall() public {
    _sync(0, 10001*1e7);
  }

  // -------------------- claim --------------------
  function testClaim() public {
    uint id = dNft.totalSupply();
    _sync(id, oracleMock.price()*2);

    dNft.claim(id);
  }
  function testCannotClaimTwice() public {
    uint id = dNft.totalSupply();
    _sync(id, oracleMock.price()*2);
    dNft.claim(id);
    vm.expectRevert(abi.encodeWithSelector(IDNft.AlreadyClaimed.selector, id, dNft.syncedBlock()));
    dNft.claim(id);
  }
  function testClaimTwice() public {
    uint id = dNft.totalSupply();
    _sync(id, oracleMock.price()*2);
    dNft.claim(id);
    vm.roll(block.number + 1);
    _sync(id, oracleMock.price()*2);
    dNft.claim(id);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft, Permission, PermissionSet} from "../src/interfaces/IDNft.sol";

contract DNftsTest is BaseTest {
  function testInsidersAllocation() public {
    assertEq(dNft.totalSupply(), GOERLI_INSIDERS.length);

    assertEq(dNft.balanceOf(GOERLI_INSIDERS[0]), 1);
    assertEq(dNft.balanceOf(GOERLI_INSIDERS[1]), 1);
    assertEq(dNft.balanceOf(GOERLI_INSIDERS[2]), 1);

    assertEq(dNft.ownerOf(0), GOERLI_INSIDERS[0]);
    assertEq(dNft.ownerOf(1), GOERLI_INSIDERS[1]);
    assertEq(dNft.ownerOf(2), GOERLI_INSIDERS[2]);

    assertTrue(dNft.ethPrice() > 0); // ethPrice is set by oracle
  }
  function testInsidersDeposit() public {
    // all insiders have the no deposit
    assertEq(dNft.idToNft(0).deposit, 0);
    assertEq(dNft.idToNft(1).deposit, 0);
    assertEq(dNft.idToNft(2).deposit, 0);

    // sanity check: dnft that does not exist has no deposit
    assertEq(dNft.idToNft(GOERLI_INSIDERS.length).deposit, 0);
  }

  // -------------------- mint --------------------
  function testMintNft() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.totalSupply(), GOERLI_INSIDERS.length + 1);
    assertEq(dNft.idToNft(id).xp, dNft.XP_MINT_REWARD());
    assertEq(uint(dNft.idToNft(id).deposit), 5 ether / 1e8 * dNft.ethPrice());
    assertEq(dNft.idToNft(id).withdrawal, 0);
    assertEq(dNft.idToNft(id).isActive, true);
  }
  function testCannotMintToZeroAddress() public {
    vm.expectRevert("ERC721: mint to the zero address");
    dNft.mint{value: 5 ether}(address(0));
  }
  function testCannotMintNotReachedMinAmount() public {
    vm.expectRevert(abi.encodeWithSelector(IDNft.DepositTooLow.selector));
    dNft.mint{value: 1 ether}(address(this));
  }
  function testCannotMintExceedsMaxSupply() public {
    uint nftsLeft = dNft.MAX_SUPPLY() - dNft.totalSupply();
    for (uint i = 0; i < nftsLeft; i++) {
      dNft.mint{value: 5 ether}(address(this));
    }
    assertEq(dNft.totalSupply(), dNft.MAX_SUPPLY());
    vm.expectRevert(abi.encodeWithSelector(IDNft.MaxSupply.selector));
    dNft.mint{value: 5 ether}(address(this));
  }

  // -------------------- exchange --------------------
  function testExchange() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));

    int depositBefore = dNft.idToNft(id).deposit;
    dNft.exchange{value: 5 ether}(id);
    int depositAfter = dNft.idToNft(id).deposit;
    assertTrue(depositAfter > depositBefore);
  }
  function testCannotExchangeDNftDoesNotExist() public {
    uint id = dNft.totalSupply();
    vm.expectRevert("ERC721: invalid token ID");
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
    vm.expectRevert(abi.encodeWithSelector(
      IDNft.MissingPermission.selector
    ));
    dNft.move(0, 2, 10000); 
  }
  function testCannotMoveDepositExceedsDepositBalance() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(
      IDNft.ExceedsDeposit.selector
    ));
    dNft.move(id, 0, 50000000 ether);
  }

  // -------------------- withdraw --------------------
  function testWithdraw() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 2000*1e18);

    uint withdrawalBefore = dNft.idToNft(id).withdrawal;
    int  depositBefore    = dNft.idToNft(id).deposit;
    dNft.withdraw(id, address(this), 1000*1e18);
    uint withdrawalAfter = dNft.idToNft(id).withdrawal;
    int  depositAfter    = dNft.idToNft(id).deposit;

    assertTrue(withdrawalAfter > withdrawalBefore);
    assertTrue(depositAfter    < depositBefore);
  }
  function testWithdrawCannotDepositAndWithdrawInSameBlock() public {
    uint id = dNft.mint{value: 50 ether}(address(this));
    dNft.exchange{value: 1 ether}(id);
    vm.expectRevert(abi.encodeWithSelector(IDNft.DepositedInSameBlock.selector));
    dNft.withdraw(id, address(this), 2000*1e18);
  }
  function testWithdrawCannotWithdrawMoreThanDeposit() public {
    uint id = dNft.mint{value: 50 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IDNft.ExceedsDeposit.selector));
    dNft.withdraw(id, address(this), 50000000 ether);
  }
  function testWithdrawCannotWithdrawCrTooLow() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 400*1e18);
    oracleMock.setPrice(0.00000001 ether);
    vm.expectRevert(abi.encodeWithSelector(IDNft.CrTooLow.selector));
    dNft.withdraw(id, address(this), 400*1e18);
  }
  function testWithdrawCannotWithdrawExceedsAverageTVL() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IDNft.ExceedsAverageTVL.selector));
    dNft.withdraw(id, address(this), 2000*1e18);
  }

  // -------------------- deposit --------------------
  function testDeposit() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 2000*1e18);
    dNft.deposit(id, 2000*1e18);
  }
  function testCannotDepositMissingPermission() public {
    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingPermission.selector));
    dNft.deposit(0, 2000*1e18);
  }
  function testCannotDepositNftIsInactive() public {
    uint id = dNft.mint{value: 50 ether}(address(this));
    dNft.deactivate(id);
    vm.expectRevert(abi.encodeWithSelector(IDNft.IsInactive.selector));
    dNft.deposit(id, 2000*1e18);
  }

  // -------------------- redeem --------------------
  function testRedeem() public {
    uint AMOUNT_TO_REDEEM = 10000;
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), AMOUNT_TO_REDEEM);

    uint oldTotalSupply = dyad.totalSupply();
    uint oldBalance = address(this).balance;
    uint oldBalanceDNftContract = address(dNft).balance;
    uint oldWithdrawal = dNft.idToNft(id).withdrawal;

    dNft.redeem  (id, address(this), AMOUNT_TO_REDEEM);

    uint newTotalSupply = dyad.totalSupply();
    uint newBalance = address(this).balance;
    uint newBalanceDNftContract = address(dNft).balance;
    uint newWithdrawal = dNft.idToNft(id).withdrawal;

    assertTrue(newTotalSupply < oldTotalSupply);
    assertTrue(newBalance > oldBalance);
    assertTrue(newBalanceDNftContract < oldBalanceDNftContract);
    assertTrue(newWithdrawal < oldWithdrawal);
  }
  function testCannotRedeemNotDNftOwner() public {
    uint AMOUNT_TO_REDEEM = 10000;
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), AMOUNT_TO_REDEEM);
    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingPermission.selector));

    dNft.redeem(0, address(this), AMOUNT_TO_REDEEM);
  }

  // -------------------- sync --------------------
  function _sync(uint id, int newPrice) internal {
    dNft.mint{value: 5 ether}(address(this));
    oracleMock.setPrice(newPrice); 
    dNft.sync(id);
  }
  function testSync() public {
    uint id          = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);

    assertEq(dNft.syncedBlock(), 0);           // syncedBlock
    assertEq(dNft.idToNft(0).xp, dNft.XP_MINT_REWARD()); // nft.xp

    uint ethPrice = dNft.ethPrice();
    _sync(id, 1100*1e8);                       // 10% price increas
    uint newEthPrice  = dNft.ethPrice();

    assertTrue(newEthPrice > ethPrice);        // ethPrice
    assertEq(dNft.prevSyncedBlock(), 0);       // prevSyncedBlock
    assertEq(dNft.syncedBlock(), block.number);// syncedBlock
    assertTrue(dNft.dyadDelta()    == 100e18); // dyadDelta
    assertEq(dNft.idToNft(id).xp, 543160);     // nft.xp
    assertEq(                                  // totalXp
      dNft.totalXp(), (dNft.XP_MINT_REWARD() * dNft.totalSupply()) + 542160
    );
    assertEq(dNft.maxXp(), dNft.idToNft(id).xp); // maxXp
  }
  function testCannotSyncPriceDidNotChange() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);
    vm.expectRevert(abi.encodeWithSelector(IDNft.EthPriceUnchanged.selector));
    dNft.sync(id);
  }

  // -------------------- claim --------------------
  function testClaimMint() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);
    _sync(id, 1100*1e8);              // 10% price increas

    /* before claim */
    assertTrue(dNft.idToNft(id).xp == 543160);           // nft.xp
    assertTrue(dNft.idToNft(id).deposit == 49000*1e18); // nft.deposit

    dNft.claim(id);

    /* after claim */
    assertEq(dNft.idToNft(id).deposit, 49094289600862480752900); // nft.deposit
    assertEq(dNft.idToNft(id).xp, 543700);                       // nft.xp
  }
  function testClaimMintRewards() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 300*1e18);
    uint xp = dNft.idToNft(id).xp;
    _sync(id, 1001*1e8);
    uint xpAfterSync = dNft.idToNft(id).xp;
    assertTrue(xpAfterSync - xp > 1000);
    dNft.claim(id);
    uint xpAfterClaim = dNft.idToNft(id).xp;
    assertTrue(xpAfterClaim - xpAfterSync > 50);
  }
  function testClaimBurn() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);
    dNft.exchange{value: 1 ether}(id);

    uint id2 = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));

    _sync(id, 900*1e8);              // 10% price decrease

    int id1DepositBefore = dNft.idToNft(id).deposit;
    int id2DepositBefore = dNft.idToNft(id2).deposit;
    assertEq(id1DepositBefore, id2DepositBefore);

    uint id1XpBefore = dNft.idToNft(id).xp;
    uint id2XpBefore = dNft.idToNft(id2).xp;

    // claim
    dNft.claim(id);
    dNft.claim(id2);

    // id1 got burned less, because he has more xp
    assertTrue(dNft.idToNft(id).deposit > dNft.idToNft(id2).deposit);

    uint id1XpAfter = dNft.idToNft(id).xp;
    uint id2XpAfter = dNft.idToNft(id2).xp;

    // xp accrual of id2 was higher, because he has less xp
    assertTrue(id2XpAfter-id2XpBefore > id1XpAfter-id1XpBefore);
  }
  function testCannotClaimTwice() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);
    _sync(id, oracleMock.price()*2);
    dNft.claim(id);
    vm.expectRevert(abi.encodeWithSelector(IDNft.AlreadyClaimed.selector));
    dNft.claim(id);
  }
  function testClaimTwice() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id, address(this), 1000*1e18);
    _sync(id, oracleMock.price()*2);
    dNft.claim(id);
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1 days);
    _sync(id, oracleMock.price()*2);
    dNft.claim(id);
  }

  // -------------------- snipe --------------------
  function testSnipeMint() public {
    uint id1 = dNft.mint{value: 50 ether}(address(this));
    uint id2 = dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id1, address(this), 1000*1e18);
    _sync(id1, 1100*1e8);              // 10% price increas
    vm.warp(block.timestamp + 1 days);
    _sync(id1, 1000*1e8);

    int id1DepositBefore = dNft.idToNft(id1).deposit;
    int id2DepositBefore = dNft.idToNft(id2).deposit;
    uint id1XpBefore = dNft.idToNft(id1).xp;
    uint id2XpBefore = dNft.idToNft(id2).xp;

    dNft.snipe(id1, id2);

    int id1DepositAfter = dNft.idToNft(id1).deposit;
    int id2DepositAfter = dNft.idToNft(id2).deposit;
    uint id1XpAfter = dNft.idToNft(id1).xp;
    uint id2XpAfter = dNft.idToNft(id2).xp;

    assertTrue(id1DepositAfter > id1DepositBefore);
    assertTrue(id2DepositAfter > id2DepositBefore);
    assertEq(id1XpAfter, id1XpBefore);
    assertTrue(id2XpAfter > id2XpBefore);
  }
  function testSnipeCannotSnipeTwice() public {
    uint id1 = dNft.mint{value: 50 ether}(address(this));
    uint id2 = dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id1, address(this), 1000*1e18);
    _sync(id1, 1100*1e8);              // 10% price increas
    vm.warp(block.timestamp + 1 days);
    _sync(id1, 1000*1e8);
    dNft.snipe(id1, id2);
    vm.expectRevert(abi.encodeWithSelector(IDNft.AlreadySniped.selector));
    dNft.snipe(id1, id2);
  }
  function testSnipeBurn() public {
    uint id1 = dNft.mint{value: 50 ether}(address(this));
    uint id2 = dNft.mint{value: 50 ether}(address(this));
    dNft.withdraw(id1, address(this), 1000*1e18);
    oracleMock.setPrice(900e8); 
    dNft.sync(id1);
    vm.warp(block.timestamp + 1 days);
    oracleMock.setPrice(1000e8); 
    dNft.sync(id1);

    int id1DepositBefore = dNft.idToNft(id1).deposit;
    int id2DepositBefore = dNft.idToNft(id2).deposit;
    uint id1XpBefore = dNft.idToNft(id1).xp;
    uint id2XpBefore = dNft.idToNft(id2).xp;

    dNft.snipe(id1, id2);

    int id1DepositAfter = dNft.idToNft(id1).deposit;
    int id2DepositAfter = dNft.idToNft(id2).deposit;
    uint id1XpAfter = dNft.idToNft(id1).xp;
    uint id2XpAfter = dNft.idToNft(id2).xp;

    assertTrue(id1DepositAfter < id1DepositBefore);
    assertEq(id2DepositAfter, id2DepositBefore);
    assertTrue(id1XpAfter > id1XpBefore);
    assertTrue(id2XpAfter > id2XpBefore);
  }

  // -------------------- liquidate --------------------
  function makeDepositNegative() public returns (uint) {
    // make the deposit of id2 negative so it becomes liquidatable
    uint id = dNft.mint{value: 85 ether}(address(this));
    dNft.withdraw(id, address(this), 100);
    oracleMock.setPrice(100000*1e8);
    dNft.withdraw(id, address(this), 80000*1e18);
    uint id2 = dNft.mint{value: 0.5 ether}(address(this));
    _sync(id, 100);
    overwriteNft(id2, dNft.idToNft(id2).xp, 100, 100);
    dNft.claim(id2);

    oracleMock.setPrice(5000*1e8);
    return id2;
  }

  function testLiquidate() public {
    uint id = makeDepositNegative();

    assertTrue(dNft.idToNft(id).deposit < 0);

    uint oldWithdrawal = dNft.idToNft(id).withdrawal;
    uint oldXp       = dNft.idToNft(id).xp;
    address oldOwner = dNft.ownerOf(id);
    dNft.liquidate{value: 2 ether}(id, address(1));
    uint newWithdrawal = dNft.idToNft(id).withdrawal;
    uint newXp       = dNft.idToNft(id).xp;
    address newOwner = dNft.ownerOf(id);

    assertTrue(newWithdrawal == oldWithdrawal);
    assertTrue(newXp > oldXp);
    assertTrue(oldOwner != newOwner);
    assertTrue(dNft.idToNft(id).deposit > 0);
  }
  function testCannotLiquidateIfDepositIsNotNegative() public {
    uint id = dNft.mint{value: 85 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotLiquidatable.selector));
    dNft.liquidate{value: 2 ether}(id, address(1));
  }
  function testCannotLiquidateNotEnoughToCoverNegativeDeposit() public {
    uint id = makeDepositNegative();
    vm.expectRevert(abi.encodeWithSelector(IDNft.DepositTooLow.selector));
    dNft.liquidate{value: 0.0001 ether}(id, address(1));
  }

  // -------------------- grant --------------------
  function testGrant() public {
    uint id = dNft.totalSupply();
    dNft.mint{value: 5 ether}(address(this));

    Permission[] memory pp = new Permission[](3);
    pp[0] = Permission.ACTIVATE;
    pp[1] = Permission.DEACTIVATE;
    pp[2] = Permission.MOVE;

    PermissionSet[] memory ps = new PermissionSet[](1);
    ps[0] = PermissionSet({ operator: address(1), permissions: pp });

    assertFalse(dNft.hasPermission(id, address(1), Permission.ACTIVATE));
    assertFalse(dNft.hasPermission(id, address(1), Permission.DEACTIVATE));

    vm.prank(address(1));
    // address(1) does not have the MOVE permission
    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingPermission.selector));
    dNft.move(id, 5, 10);

    dNft.grant(id, ps);

    assertTrue (dNft.hasPermission(id, address(1), Permission.ACTIVATE));
    assertTrue (dNft.hasPermission(id, address(1), Permission.DEACTIVATE));
    assertTrue (dNft.hasPermission(id, address(1), Permission.MOVE));
    assertFalse(dNft.hasPermission(id, address(1), Permission.REDEEM));

    Permission[] memory p = new Permission[](4);
    p[0] = Permission.ACTIVATE;
    p[1] = Permission.DEACTIVATE;
    p[2] = Permission.MOVE;
    p[3] = Permission.REDEEM;

    bool[] memory hp = dNft.hasPermissions(id, address(1), p);
    assertTrue (hp[0]);
    assertTrue (hp[1]);
    assertTrue (hp[2]);
    assertFalse(hp[3]);

    // address(1) now has the permission to call move
    vm.prank(address(1));
    dNft.move(id, 5, 10);
  }
}

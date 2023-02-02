// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

// import "forge-std/console.sol";
// import {BaseTest} from "./BaseTest.sol";
// import {Parameters} from "../src/Parameters.sol";
// import {IDNft, Permission, PermissionSet} from "../src/interfaces/IDNft.sol";

// contract DNftsTest is BaseTest {
//   function testInsidersAllocation() public {
//     assertEq(dNft.totalSupply(), GOERLI_INSIDERS.length);

//     assertEq(dNft.balanceOf(GOERLI_INSIDERS[0]), 1);
//     assertEq(dNft.balanceOf(GOERLI_INSIDERS[1]), 1);
//     assertEq(dNft.balanceOf(GOERLI_INSIDERS[2]), 1);

//     assertEq(dNft.ownerOf(0), GOERLI_INSIDERS[0]);
//     assertEq(dNft.ownerOf(1), GOERLI_INSIDERS[1]);
//     assertEq(dNft.ownerOf(2), GOERLI_INSIDERS[2]);

//     assertTrue(dNft.ethPrice() > 0); // ethPrice is set by oracle
//   }
//   function testInsidersDeposit() public {
//     // all insiders have the no deposit
//     assertEq(dNft.idToNft(0).deposit, 0);
//     assertEq(dNft.idToNft(1).deposit, 0);
//     assertEq(dNft.idToNft(2).deposit, 0);

//     // sanity check: dnft that does not exist has no deposit
//     assertEq(dNft.idToNft(GOERLI_INSIDERS.length).deposit, 0);
//   }

//   // -------------------- mint --------------------
//   function testMintNft() public {
//     uint id = dNft.totalSupply();
//     dNft.mint{value: 5 ether}(address(this));
//     assertEq(dNft.totalSupply(), GOERLI_INSIDERS.length + 1);
//     assertEq(dNft.idToNft(id).xp, dNft.XP_MINT_REWARD());
//     assertEq(uint(dNft.idToNft(id).deposit), 5 ether / 1e8 * dNft.ethPrice());
//     assertEq(dNft.idToNft(id).withdrawal, 0);
//     assertEq(dNft.idToNft(id).isActive, true);
//   }
//   function testCannotMintToZeroAddress() public {
//     vm.expectRevert("ERC721: mint to the zero address");
//     dNft.mint{value: 5 ether}(address(0));
//   }
//   function testCannotMintNotReachedMinAmount() public {
//     vm.expectRevert(abi.encodeWithSelector(IDNft.DepositTooLow.selector));
//     dNft.mint{value: 1 ether}(address(this));
//   }
//   function testCannotMintExceedsMaxSupply() public {
//     uint nftsLeft = dNft.MAX_SUPPLY() - dNft.totalSupply();
//     for (uint i = 0; i < nftsLeft; i++) {
//       dNft.mint{value: 5 ether}(address(this));
//     }
//     assertEq(dNft.totalSupply(), dNft.MAX_SUPPLY());
//     vm.expectRevert(abi.encodeWithSelector(IDNft.MaxSupply.selector));
//     dNft.mint{value: 5 ether}(address(this));
//   }
// }

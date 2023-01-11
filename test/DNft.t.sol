// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract DNftsTest is BaseTest, Parameters {
  function testInsidersAllocation() public {
    assertEq(DNft.totalSupply(), INSIDERS.length);

    assertEq(DNft.balanceOf(INSIDERS[0]), 1);
    assertEq(DNft.balanceOf(INSIDERS[1]), 1);
    assertEq(DNft.balanceOf(INSIDERS[2]), 1);

    assertEq(DNft.ownerOf(0), INSIDERS[0]);
    assertEq(DNft.ownerOf(1), INSIDERS[1]);
    assertEq(DNft.ownerOf(2), INSIDERS[2]);
  }
  function testMintNft() public {
    DNft.mintNft{value: 5 ether}(address(this));
    assertEq(DNft.totalSupply(), INSIDERS.length + 1);
  }
  function testFailMintToZeroAddress() public {
    DNft.mintNft(address(0));
  }
  function testFailMintNoEthSupplied() public {
    DNft.mintNft(address(this));
  }
  function testFailMintNotReachedMinAmount() public {
    DNft.mintNft{value: 1 ether}(address(this));
  }
  function testFailMintExceedsMaxSupply() public {
    uint nftsLeft = DNft.maxSupply() - DNft.totalSupply();
    for (uint i = 0; i < nftsLeft; i++) {
      DNft.mintNft(address(this));
    }
    assertEq(DNft.totalSupply(), DNft.maxSupply());
    DNft.mintNft(address(this));
  }
}

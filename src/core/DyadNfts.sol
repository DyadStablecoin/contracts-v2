// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {Dyad} from "./Dyad.sol";

contract DyadNfts is ERC721Enumerable {
  uint public constant MAX_SUPPLY = 10000;

  mapping(uint256 => DyadNftData) public getDyadNftData;

  Dyad public dyad;

  struct DyadNftData {
    uint xp;
  }

  constructor(
    address _dyad,
    address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
    dyad      = Dyad(_dyad);

    for (uint id = 0; id < _insiders.length; ) { 
      // _mintNft(_insiders[id], id, true);         
      unchecked { ++id; }
    }
  }
}

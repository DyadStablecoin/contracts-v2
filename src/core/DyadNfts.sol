// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {Dyad} from "./Dyad.sol";

contract DyadNfts is ERC721Enumerable {
  uint public immutable MAX_SUPPLY;                

  mapping(uint256 => DyadNftData) public getDyadNftData;

  Dyad public dyad;

  struct DyadNftData {
    uint xp;
  }

  constructor(
    address _dyad,
    uint    _maxSupply
  ) ERC721("Dyad NFT", "dNFT") {
    dyad       = Dyad(_dyad);
    MAX_SUPPLY = _maxSupply;
  }
}

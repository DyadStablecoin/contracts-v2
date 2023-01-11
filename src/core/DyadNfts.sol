// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract DyadNfts is ERC721Enumerable {
  constructor() ERC721("DYAD NFT", "dNFT") {}

  mapping(uint256 => DyadNftData) public getDyadNftData;

  struct DyadNftData {
    uint xp;
  }
}

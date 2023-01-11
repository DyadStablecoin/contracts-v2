// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {Dyad} from "./Dyad.sol";

contract DNfts is ERC721Enumerable {
  uint public constant MAX_SUPPLY = 10000;

  mapping(uint256 => Nft) public idToNft;

  Dyad public dyad;

  struct Nft {
    uint xp;
    uint deposit;
    uint credit;
    uint creditScore;
  }

  event NftMinted(address indexed to, uint indexed id);

  error ReachedMaxSupply();

  constructor(
    address _dyad,
    address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
    dyad      = Dyad(_dyad);

    for (uint i = 0; i < _insiders.length; ) { 
      _mintNft(_insiders[i], i);
      unchecked { ++i; }
    }
  }

    // Mint new dNFT to `to` with `id` id 
  function _mintNft(
    address to,
    uint id
  ) private {
    if (id >= MAX_SUPPLY) { revert ReachedMaxSupply(); }
    _mint(to, id); 
    // unchecked {
    idToNft[id].xp = (MAX_SUPPLY<<1) - id; // break xp symmetry 
    // }
    emit NftMinted(to, id);
  }
}

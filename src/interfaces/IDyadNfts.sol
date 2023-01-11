// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDyadNfts {
  struct Nft {
    uint xp;
    uint deposit;
  }

  /**
   * @notice Get dNFT by id
   * @param id dNFT id
   * @return dNFT 
   */
  function idToNft(
    uint id
  ) external view returns (Nft memory);


  // ERC721
  function ownerOf(uint tokenId) external view returns (address);
  function balanceOf(address owner) external view returns (int);
  function totalSupply() external view returns (uint);
  function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
}


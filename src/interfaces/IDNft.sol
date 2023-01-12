// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  struct Nft {
    uint xp;
    uint deposit;
    uint withdrawal;
    uint credit;
    uint creditScore;
  }

  function idToNft( uint id) external view returns (Nft memory);

  function mintNft    (address to) external payable;
  function deposit    (uint id) external payable;
  function moveDeposit(uint from, uint to, uint amount) external payable;
  function withdraw   (uint id, uint amount) external payable;
  function redeem     (uint id, uint amount) external payable;
  function burn       (uint id, uint amount) external payable;

  function MAX_SUPPLY() external pure returns (uint);

  // ERC721
  function ownerOf(uint tokenId) external view returns (address);
  function balanceOf(address owner) external view returns (int);
  function totalSupply() external view returns (uint);
}

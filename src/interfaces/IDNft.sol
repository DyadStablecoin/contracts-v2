// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  struct Nft {
    uint xp;                  // always inflationary
    int  deposit;             // deposited DYAD
    uint withdrawal;          // withdrawn DYAD
    uint lastOwnershipChange; // block number of the last ownership change
    bool isActive;
  }

  event Minted(address indexed to, uint indexed id);

  error MaxSupply();
}

// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@solmate/src/tokens/ERC20.sol";
import "@solmate/src/auth/Owned.sol";

contract Dyad is ERC20, Owned {
  constructor() ERC20("DYAD Stablecoin", "DYAD", 18) Owned(msg.sender) {}

  function mint(address to,   uint amount) public onlyOwner { _mint(to,   amount); }
  function burn(address from, uint amount) public onlyOwner { _burn(from, amount); }
}

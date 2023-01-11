// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Dyad is ERC20, Ownable {
  constructor() ERC20("DYAD Stablecoin", "DYAD") {}

  function mint(address to,   uint amount) public onlyOwner { _mint(to,   amount); }
  function burn(address from, uint amount) public onlyOwner { _burn(from, amount); }
}

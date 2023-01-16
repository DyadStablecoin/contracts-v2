// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {Dyad} from "../src/core/Dyad.sol";
import {OracleMock} from "./OracleMock.sol";

contract BaseTest is Test {
  IDNft      dNft;
  Dyad       dyad;
  OracleMock oracleMock;

  receive() external payable {}

  function setUp() public {
    oracleMock = new OracleMock();
    DeployBase deployBase = new DeployBase();
    (address _dNfts, address _dyad) = deployBase.deploy(address(oracleMock));
    dNft = IDNft(_dNfts);
    dyad = Dyad(_dyad);
  }

}

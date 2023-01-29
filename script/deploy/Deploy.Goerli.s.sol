// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {Parameters} from "../../src/Parameters.sol";

contract DeployGoerli is Script, Parameters {
  function run() public {
      new DeployBase().deploy(
        GOERLI_ORACLE,
        GOERLI_MAX_SUPPLY,
        GOERLI_MIN_TIME_BETWEEN_SYNC,
        GOERLI_MIN_MINT_DYAD_DEPOSIT,
        GOERLI_INSIDERS
      );
  }
}

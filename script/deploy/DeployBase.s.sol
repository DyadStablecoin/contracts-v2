// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Script.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {DNfts} from "../../src/core/DNfts.sol";
import {Parameters} from "../../src/Parameters.sol";

contract DeployBase is Script, Parameters {
  function deploy() public returns (address, address) {
    vm.startBroadcast();

    Dyad     dyad  = new Dyad();
    DNfts dyadNfts = new DNfts(address(dyad), INSIDERS);

    dyad.transferOwnership(address(dyadNfts));

    vm.stopBroadcast();
    return (address(dyadNfts), address(dyad));
  }
}

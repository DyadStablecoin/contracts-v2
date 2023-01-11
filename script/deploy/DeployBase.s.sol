// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Script.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {DyadNfts} from "../../src/core/DyadNfts.sol";

contract DeployBase is Script {
  function deploy() public returns (address, address) {
    vm.startBroadcast();

    Dyad     dyad     = new Dyad();
    DyadNfts dyadNfts = new DyadNfts(address(dyad));

    dyad.transferOwnership(address(dyadNfts));

    vm.stopBroadcast();
    return (address(dyadNfts), address(dyad));
  }
}

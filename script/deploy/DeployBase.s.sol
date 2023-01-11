// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Script.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {DyadNfts} from "../../src/core/DyadNfts.sol";

contract Deployment is Script {

  function deploy(uint _maxSupply) public {
    vm.startBroadcast();

    Dyad     dyad     = new Dyad();
    DyadNfts dyadNfts = new DyadNfts(address(dyad), _maxSupply);

    dyad.transferOwnership(address(dyadNfts));

    vm.stopBroadcast();
  }

}

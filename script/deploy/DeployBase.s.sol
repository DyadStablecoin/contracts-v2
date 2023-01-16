// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Script.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {DNft} from "../../src/core/DNft.sol";
import {Parameters} from "../../src/Parameters.sol";

contract DeployBase is Script, Parameters {
  function deploy(address _oracle) public returns (address, address) {
    vm.startBroadcast();

    Dyad dyad = new Dyad();
    DNft dNft = new DNft(
      address(dyad),
      _oracle,
      DEPOSIT_MIMIMUM,
      INSIDERS
    );

    dyad.transferOwnership(address(dNft));

    vm.stopBroadcast();
    return (address(dNft), address(dyad));
  }
}

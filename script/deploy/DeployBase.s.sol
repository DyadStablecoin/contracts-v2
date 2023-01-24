// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Script.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {DNft} from "../../src/core/DNft.sol";
import {IDNft} from "../../src/interfaces/IDNft.sol";
import {Claimer} from "../../src/composing/Claimer.sol";
import {Parameters} from "../../src/Parameters.sol";

contract DeployBase is Script, Parameters {
  function deploy(
    address _oracle, 
    uint    _maxSupply,
    uint    _minPriceChangeBetweenSync,
    uint    _minTimeBetweenSync,
    int     _minMintDyadDeposit, 
    address[] memory _insiders
  ) public payable returns (
    address,
    address,
    address
  ) {
    vm.startBroadcast();

    Dyad dyad = new Dyad();
    DNft dNft = new DNft(
      address(dyad),
      _oracle,
      _maxSupply,
      _minPriceChangeBetweenSync,
      _minTimeBetweenSync,
      _minMintDyadDeposit, 
      _insiders
    );
    Claimer claimer = new Claimer(
      IDNft(address(dNft)), 
      Claimer.Config(FEE, FEE_COLLECTOR, MAX_STAKER)
    );

    dyad.transferOwnership(address(dNft));

    vm.stopBroadcast();
    return (address(dNft), address(dyad), address(claimer));
  }
}

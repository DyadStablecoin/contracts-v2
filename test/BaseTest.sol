// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DeployBase} from "../script/deploy/DeployBase.s.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {Dyad} from "../src/core/Dyad.sol";
import {OracleMock} from "./OracleMock.sol";
import {Parameters} from "../src/Parameters.sol";

contract BaseTest is Test, Parameters {
  using stdStorage for StdStorage;

  IDNft      dNft;
  Dyad       dyad;
  OracleMock oracleMock;

  receive() external payable {}

  function setUp() public {
    oracleMock = new OracleMock();
    DeployBase deployBase = new DeployBase();
    (address _dNfts, address _dyad) = deployBase.deploy(
      address(oracleMock),
      MAINNET_MAX_SUPPLY,
      MAINNET_MIN_TIME_BETWEEN_SYNC,
      MAINNET_MIN_MINT_DYAD_DEPOSIT,
      GOERLI_INSIDERS
    );
    dNft    = IDNft(_dNfts);
    dyad    = Dyad(_dyad);
    vm.warp(block.timestamp + 1 days);
  }

  function overwriteNft(uint id, uint xp, uint deposit, uint withdrawal) public {
    stdstore.target(address(dNft)).sig("idToNft(uint256)").with_key(id)
      .depth(0).checked_write(xp);
    stdstore.target(address(dNft)).sig("idToNft(uint256)").with_key(id)
      .depth(1).checked_write(deposit);
    stdstore.target(address(dNft)).sig("idToNft(uint256)").with_key(id)
      .depth(2).checked_write(withdrawal);
  }

  function overwrite(address _contract, string memory signature, uint value) public {
    stdstore.target(_contract).sig(signature).checked_write(value); 
  }
}

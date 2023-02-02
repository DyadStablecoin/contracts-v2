// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@solmate/src/utils/ReentrancyGuard.sol";
import {wadDiv, wadMul} from "@solmate/src/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {IDNft} from "../interfaces/IDNft.sol";
import {Dyad} from "./Dyad.sol";

contract DNft is IDNft, ERC721Enumerable, ReentrancyGuard {
  uint public immutable MAX_SUPPLY;            // Max supply of DNfts
  int  public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft

  Dyad public dyad;
  IAggregatorV3 internal oracle;

  constructor(
      address _dyad,
      address _oracle, 
      uint    _maxSupply,
      uint    _minTimeBetweenSync,
      int     _minMintDyadDeposit, 
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
      MAX_SUPPLY            = _maxSupply;
      MIN_MINT_DYAD_DEPOSIT = _minMintDyadDeposit;
  }
}

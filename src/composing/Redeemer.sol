// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

// import {IDNft, Permission} from "../interfaces/IDNft.sol";
// import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

// contract Redeemer {
//   using FixedPointMathLib for uint256;

//   struct Position {
//     uint fee;
//     uint redemptionLimit;
//   }

//   IDNft public dNft;
//   mapping(uint => Position) public  idToPosition;
//   mapping(uint => uint)     private _idToFees;

//   error NotNFTOwner           (uint id);
//   error RedemptionLimitReached();
//   error MissingPermission     ();

//   modifier onlyOwner(uint id) {
//     if (dNft.ownerOf(id) != msg.sender) revert NotNFTOwner(id);
//     _;
//   }

//   constructor(IDNft _dNft) {
//     dNft = _dNft;
//   }

//   function modify(uint id, Position calldata position) external onlyOwner(id) {
//     idToPosition[id] = position;
//   }

//   function add(uint id, Position calldata position) external onlyOwner(id) {
//     if (!dNft.hasPermission(id, address(this), Permission.REDEEM)) revert MissingPermission();
//     idToPosition[id] = position;
//   }

//   function remove(uint id) external onlyOwner(id) {
//     delete idToPosition[id];
//   }

//   function redeem(uint id, uint amount, address to) external {
//     Position  memory position = idToPosition[id];
//     IDNft.Nft memory nft     = dNft.idToNft(id);
//     if (nft.withdrawal - amount < position.redemptionLimit) revert RedemptionLimitReached();
//     uint eth = dNft.redeem(id, address(this), amount);
//     uint fee = eth.mulWadDown(position.fee);
//     _idToFees[id] += fee;
//     payable(to).transfer(eth - fee);
//   }

//   function claim(uint id, address to) external onlyOwner(id) {
//     _idToFees[id] = 0;
//     payable(to).transfer(_idToFees[id]);
//   }
// }

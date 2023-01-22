// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {IDNft, Permission} from "../interfaces/IDNft.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

contract Redeemer {
  using FixedPointMathLib for uint256;

  struct Position {
    uint fee;
    uint redemptionLimit;
    address feeRecipient;
  }

  IDNft public dNft;
  mapping(uint => Position) public  idToPosition;
  mapping(uint => uint)     private _idToFees;

  modifier onlyOwner(uint id) {
    require(dNft.ownerOf(id) == msg.sender);
    _;
  }

  constructor(IDNft _dNft) {
    dNft = _dNft;
  }

  function modify(uint id, Position calldata position) external onlyOwner(id) {
    idToPosition[id] = position;
  }

  function add(uint id, Position calldata position) external onlyOwner(id) {
    require(dNft.hasPermission(id, address(this), Permission.REDEEM));
    idToPosition[id] = position;
  }

  function remove(uint id) external onlyOwner(id) {
    delete idToPosition[id];
  }

  function redeem(uint id, uint amount, address to) external {
    Position  memory position = idToPosition[id];
    IDNft.Nft memory nft     = dNft.idToNft(id);
    require(nft.withdrawal - amount > position.redemptionLimit);
    uint eth = dNft.redeem(id, address(this), amount);
    uint fee = eth.mulWadDown(position.fee);
    _idToFees[id] += fee;
    payable(to).transfer(eth - fee);
  }

  function claim(uint id) external onlyOwner(id) {
    Position memory position = idToPosition[id];
    _idToFees[id] = 0;
    payable(position.feeRecipient).transfer(_idToFees[id]);
  }
}

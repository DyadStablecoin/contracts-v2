// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import {DNft} from "../core/DNft.sol";

// /// @title Permission Math library
// /// @notice Provides functions to easily convert from permissions to an int representation and viceversa
// /// @notice Copy/Pasta from here: https://github.com/Mean-Finance/dca-v2-core/blob/main/contracts/libraries/PermissionMath.sol
// library PermissionMath {
//   /// @notice Takes a list of permissions and returns the int representation of the set that contains them all
//   /// @param _permissions The list of permissions
//   /// @return _representation The uint representation
//   function _toUInt8(DNft.Permission[] memory _permissions) internal pure returns (uint8 _representation) {
//     for (uint256 i = 0; i < _permissions.length; ) {
//       _representation |= uint8(1 << uint8(_permissions[i]));
//       unchecked {
//         i++;
//       }
//     }
//   }

//   /// @notice Takes an int representation of a set of permissions, and returns whether it contains the given permission
//   /// @param _representation The int representation
//   /// @param _permission The permission to check for
//   /// @return hasPermission Whether the representation contains the given permission
//   function _hasPermission(
//       uint8 _representation, 
//       DNft.Permission _permission
//   ) internal pure returns (bool hasPermission) {
//       uint256 _bitMask = 1 << uint8(_permission);
//       hasPermission = (_representation & _bitMask) != 0;
//   }
// }


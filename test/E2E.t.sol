// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract E2ETest is BaseTest, Parameters {
  function setNfts() internal {
    overwriteNft(0, 2161, 146,  3920 );
    overwriteNft(1, 7588, 4616, 7496 );
    overwriteNft(2, 3892, 2731, 10644);
    overwriteNft(3, 3350, 4515, 2929 );
    overwriteNft(4, 3012, 2086, 3149 );
    overwriteNft(5, 5496, 7241, 7127 );
    overwriteNft(6, 8000, 8197, 7548 );
    overwriteNft(7, 7000, 5873, 9359 );
    overwriteNft(8, 3435, 1753, 4427 );
    overwriteNft(9, 1079, 2002, 244  );

    overwrite("lastEthPrice()", 100000000000000000000000);
  }

  function testMint() public {

    console.log(dNft.lastEthPrice());
    overwriteNft(0, 100, 200, 400);
    setNfts();
    console.log(dNft.lastEthPrice());
  }
}


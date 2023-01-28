// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";

contract E2ETest is BaseTest {
  function setNfts() internal {
    overwriteNft(0, 2161, 146 *1e18, 3920 );
    overwriteNft(1, 7588, 4616*1e18, 7496 );
    overwriteNft(2, 3892, 2731*1e18, 10644);
    overwriteNft(3, 3350, 4515*1e18, 2929 );
    overwriteNft(4, 3012, 2086*1e18, 3149 );
    overwriteNft(5, 5496, 7241*1e18, 7127 );
    overwriteNft(6, 8048, 8197*1e18, 7548 );
    overwriteNft(7, 7333, 5873*1e18, 9359 );
    overwriteNft(8, 3435, 1753*1e18, 4427 );
    overwriteNft(9, 1079, 2002*1e18, 244  );

    overwrite(address(dNft), "lastEthPrice()", 100000000000000000000000);

    uint withdrawalSum;
    for (uint i = 0; i < dNft.totalSupply(); i++) {
      withdrawalSum += dNft.idToNft(i).withdrawal;
    }
    overwrite(address(dyad), "totalSupply()", withdrawalSum*1e18);

    uint xpSum;
    for (uint i = 0; i < dNft.totalSupply(); i++) {
      xpSum += dNft.idToNft(i).xp;
    }
    overwrite(address(dNft), "totalXp()", xpSum);
  }

  function testE2eClaimMint() public {
    startHoax(dNft.ownerOf(0));
    setNfts();
    dNft.activate(0);
    overwrite(address(dNft), "lastEthPrice()", 100000000000);
    oracleMock.setPrice(110000000000);
    dNft.sync(0);

    overwriteNft(0, 2161.00, 10_000e18, dNft.idToNft(0).withdrawal);
    overwrite(address(dNft), "totalXp()", 45394);
    overwrite(address(dNft), "dyadDelta()", 15523e18);
    overwrite(address(dNft), "totalDeposit()", 100_000e18);
    dNft.claim(0);

    assertEq(dNft.idToNft(0).deposit/1e18, 11145);
    vm.stopPrank();

    overwrite(address(dNft), "totalXp()", 45394);
    startHoax(dNft.ownerOf(1));
    dNft.activate(1);
    overwriteNft(1, dNft.idToNft(1).xp, 10_000e18, dNft.idToNft(0).withdrawal);
    dNft.claim(1);
    assertEq(dNft.idToNft(1).deposit/1e18, 12064);
  }

  function testE2eClaimBurn() public {
    startHoax(dNft.ownerOf(0));
    setNfts();
    overwrite(address(dyad), "totalSupply()", 155233e18);
    dNft.activate(0);
    overwrite(address(dNft), "lastEthPrice()", 100000000000);
    oracleMock.setPrice(90000000000);
    dNft.sync(0);

    overwriteNft(0, 2161.00, 10_000e18, 3920e18);
    overwrite(address(dyad), "totalSupply()", 156843e18);
    overwrite(address(dNft), "totalXp()", 45394);
    overwrite(address(dNft), "maxXp()", 8048);
    overwrite(address(dNft), "totalSupply()", 10);

    dNft.claim(0);
    assertEq(dNft.idToNft(0).deposit/1e18, 8008);
    assertEq(dNft.idToNft(0).xp, 11008);
  }
}

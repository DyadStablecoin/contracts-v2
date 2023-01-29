// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

contract Parameters {

  // ---------------- Goerli ----------------
  address[] GOERLI_INSIDERS = [
    0x7EEfFd5D089b1351ecCC388022d8b823676dF424, // cryptohermetica
    0xCAD2EaDA97Ad393584Fe84A5cCA1ef3093E45ae4, // joeyroth.eth
    0x414b60745072088d013721b4a28a0559b1A9d213, // shafu.eth
    0x3682827F48F8E023EE40707dEe82620D0B63579f, // Max Entropy
    0xe779Fb090AF9dfBB3b4C18Ed571ad6390Df52ae2, // dma.eth
    0x9F919a292e62594f2D8db13F6A4ADB1691D6c60d, // kores
    0x1b8afB86A36134691Ef9AFba90F143d9b5e8aBbB, // e_z.eth
    0xe9fC93E678F2Bde7A0a3bA3d39F505Ef63a68C97, // ehjc
    0x78965cecb4696165B374FeA43Bac3029006Dec2c, // 0xMurathan
    0xE264df996EF2934b8134AA1A03354F1FCd547939, // Ziad
    0xC9c1281148460E075AD5dEFA856dAc005773A2A6  // sdk
  ];
  address GOERLI_ORACLE = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
  uint GOERLI_MAX_SUPPLY                    = 2000;
  uint GOERLI_MIN_TIME_BETWEEN_SYNC         = 5 minutes;
  int  GOERLI_MIN_MINT_DYAD_DEPOSIT         = 1e18;

  // ---------------- Mainnet ----------------
  address[] MAINNET_INSIDERS = [ //TODO: still to be determined
    0x414b60745072088d013721b4a28a0559b1A9d213, 
    0x414b60745072088d013721b4a28a0559b1A9d213, 
    0x414b60745072088d013721b4a28a0559b1A9d213, 
    0x414b60745072088d013721b4a28a0559b1A9d213, 
    0x414b60745072088d013721b4a28a0559b1A9d213
  ];
  address MAINNET_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
  uint MAINNET_MAX_SUPPLY                    = 10_000;
  uint MAINNET_MIN_TIME_BETWEEN_SYNC         = 10 minutes;
  int  MAINNET_MIN_MINT_DYAD_DEPOSIT         = 5000e18; // 5k

  // ---------------- AutoClaim ----------------
  int  FEE           = 0.01e18;
  uint FEE_COLLECTOR = 0;       // dNft id of fee collector
  uint MAX_NUMBER_OF_CLAIMERS = 20;
}


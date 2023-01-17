// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

contract Parameters {
  address[] INSIDERS = [
    0x7EEfFd5D089b1351ecCC388022d8b823676dF424, // cryptohermetica
    0xCAD2EaDA97Ad393584Fe84A5cCA1ef3093E45ae4, // joeyroth.eth
    0x414b60745072088d013721b4a28a0559b1A9d213, // shafu.eth
    0x3682827F48F8E023EE40707dEe82620D0B63579f, // Max Entropy
    0xe779Fb090AF9dfBB3b4C18Ed571ad6390Df52ae2, // dma.eth
    0x9F919a292e62594f2D8db13F6A4ADB1691D6c60d, // kores
    0x1b8afB86A36134691Ef9AFba90F143d9b5e8aBbB, // e_z.eth
    0xe9fC93E678F2Bde7A0a3bA3d39F505Ef63a68C97, // ehjc
    0x78965cecb4696165B374FeA43Bac3029006Dec2c, // 0xMurathan
    0xE264df996EF2934b8134AA1A03354F1FCd547939  // Ziad
  ];

  int constant DEPOSIT_MIMIMUM = 5000000000000000000000; // 5,000 DYAD

  address ORACLE_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
  address ORACLE_GOERLI  = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
}


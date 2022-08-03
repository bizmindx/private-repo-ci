const { ethers } = require("hardhat");

export const SIGNER_ACCOUNT = {
  publicKey: "0xC6C23De51657dd9C2C4F921Ffa66CCFe3C2FbFD9",
  privateKey: Buffer.from(
    "4626faca3179addddacb3cb60ba3fe5b0943d11de9afbded0154b379df7ba5f4",
    "hex"
  ),
};

export const createPoolNewAddress = () => {
  const { address } = new ethers.Wallet.createRandom();
  return ethers.utils.getAddress(address);
};

export const advanceBlocks = async (numberOfBlocks: number) => {
  for (let index = 0; index < numberOfBlocks; index++) {
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");
  }
};

export const weiToEth = (balance: any) => {
  return ethers.utils.formatEther(balance);
};

export const ethToWei = (balance: any) => {
  return ethers.utils.parseEther(balance);
};

export const increaseTime = async (seconds) => {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
};

export const setBlockTime = async (blockTime = 1625097600) => {
  await ethers.provider.send("evm_setNextBlockTimestamp", [blockTime]);
  await ethers.provider.send("evm_mine", []);
};

const { ethers } = require("hardhat");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");

const SIGNER_ACCOUNT = {
  publicKey: "0xC6C23De51657dd9C2C4F921Ffa66CCFe3C2FbFD9",
  privateKey: Buffer.from(
    "4626faca3179addddacb3cb60ba3fe5b0943d11de9afbded0154b379df7ba5f4",
    "hex"
  ),
};

const createPoolNewAddress = () => {
  const address = web3.eth.accounts.create();
  return web3.utils.toChecksumAddress(address.address);
};

const advanceBlocks = async (numberOfBlocks) => {
  for (let index = 0; index < numberOfBlocks; index++) {
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");
  }
};

module.exports = {
  createPoolNewAddress,
  advanceBlocks,
  SIGNER_ACCOUNT
}
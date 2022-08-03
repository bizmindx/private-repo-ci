import { expect } from "chai";
import { ethers } from "hardhat";
import fsdContractsDeployer from "../../helpers/test.deployer";

describe("Final Minting", async () => {
  // Accounts
  let owner;

  // Premine
  let premineAccount1;
  let premineAccount2;
  let premineAccount3;
  let premineAccount4;

  // Malicious
  let random;

  let minter;

  let fsd;
  let fundingPool;

  before(async () => {
    [
      owner,
      premineAccount1,
      premineAccount2,
      premineAccount3,
      premineAccount4,
      random,
    ] = await ethers.getSigners();

    ({ fsd, fundingPool, minter } = await fsdContractsDeployer(owner));

    //move to final phase
    await fsd.updateCurrentPhase(4);
  });

  it("should mint in the final phase", async () => {
    // mint tokens for 1 ether
    await minter.connect(premineAccount1).mint(1, {
      value: ethers.utils.parseEther("1"),
    });

    // make sure we have tokens minted
    expect(await fsd.balanceOf(premineAccount1.address)).to.not.be.equal(0);

    //TODO break down into new test case
    // // // Make sure that we are splitting 30/70
    // expect(await ethers.provider.getBalance(fundingPool)).to.equal(
    //     ethers.utils.parseEther("459.3")
    // );
    // expect(await ethers.provider.getBalance(fsd.address)).to.equal(
    //     ethers.utils.parseEther("1071.7")
    // );
  });

  it("should add ETH after the 500 limit to funding pool has achieved and check allocations", async () => {
    // Add 500 Ether to funding pool
    await minter.connect(premineAccount2).mint(1, {
      value: ethers.utils.parseEther("1000"),
    });
    await minter.connect(premineAccount3).mint(1, {
      value: ethers.utils.parseEther("667"),
    });

    const fundingpoolBalance = await ethers.provider.getBalance(fundingPool);

    // make sure we are not collecting anymore for funding pool
    await minter.connect(premineAccount4).mint(1, {
      value: ethers.utils.parseEther("100"),
    });

    expect(await ethers.provider.getBalance(fundingPool)).to.be.equal(
      fundingpoolBalance
    );
  });

  it("should burn FSD for ETH", async () => {
    //TODO Fix
    // try to burn from a bad account
    // expect(await fsd.connect(random).burn(0, 10000)).to.be.reverted;
    // const balanceBefore = await fsd.balanceOf(premineAccount1.address);
    // await fsd.connect(premineAccount1).burn(100, 100);
    // const balanceAfter = await fsd.balanceOf(premineAccount1.address);
    // expect(balanceBefore).to.not.be.equal(balanceAfter);
  });
});

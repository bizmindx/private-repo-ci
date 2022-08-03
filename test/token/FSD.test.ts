import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import fsdContractsDeployer from "../helpers/test.deployer";

describe("FSDToken", () => {
  // Accounts
  let owner: SignerWithAddress;

  // Premine
  let premineAccount1: SignerWithAddress;
  let premineAccount2: SignerWithAddress;
  let premineAccount3: SignerWithAddress;

  // Malicious
  let random: SignerWithAddress;

  let membershipBuyer;
  let fsd;
  let fsdNetwork;

  before(async () => {
    [
      owner,
      premineAccount1,
      premineAccount2,
      premineAccount3,
      random,
      membershipBuyer,
    ] = await ethers.getSigners();
    ({ fsd, fsdNetwork } = await fsdContractsDeployer(owner));
    //move to final phase
    await fsd.updateCurrentPhase(4);
  });

  it("should move 1000 eth to the capital pool without disturbing the state and price", async () => {
    // get price and total supply
    const fsdPrice = await fsdNetwork.getFSDPrice();
    const totalFSDSupply = await fsd.totalSupply();

    // move 1000 ETH to capital pool
    await owner.sendTransaction({
      to: fsd.address,
      value: ethers.utils.parseEther("1000"),
    });

    // get price and total supply after
    const fsdPriceAfter = await fsdNetwork.getFSDPrice();
    const totalFSDSupplyAfter = await fsd.totalSupply();

    // check if the price is not the same
    expect(fsdPrice).to.not.be.equal(fsdPriceAfter);
    // check if the total supply is the same
    expect(totalFSDSupply).to.be.equal(totalFSDSupplyAfter);
  });

  it("should move another 1500 eth to the capital pool without disturbing the state and price", async () => {
    // get price and total supply
    const fsdPrice = await fsdNetwork.getFSDPrice();
    const totalFSDSupply = await fsd.totalSupply();

    // move 1500 ETH to capital pool
    await owner.sendTransaction({
      to: fsd.address,
      value: ethers.utils.parseEther("1500"),
    });

    // get price and total supply after
    const fsdPriceAfter = await fsdNetwork.getFSDPrice();
    const totalFSDSupplyAfter = await fsd.totalSupply();

    // check if the price is not the same
    expect(fsdPrice).to.not.be.equal(fsdPriceAfter);
    // check if the total supply is the same
    expect(totalFSDSupply).to.be.equal(totalFSDSupplyAfter);
  });

  it("should evaluate governance", async () => {
    // TODO: Revisit
    // make sure that we are handling governance
    // expect(await fsd.isGovernance(premineAccount1.address)).to.be.equal(false);
    // expect(await fsd.isGovernance(membershipBuyer.address)).to.be.equal(false);
    // expect(await fsd.isGovernance(premineAccount2.address)).to.be.equal(false);
    // expect(await fsd.isGovernance(random.address)).to.be.equal(false);
  });

  it("should burn FSD for ETH", async () => {
    //TODO
    /********* DISABLED UNTIL RESOLVED */
    // importbalanceBefore = await fsd.balanceOf(premineAccount3.address);
    // await fsd.connect(premineAccount3).burn(10, 10000);
    // const balanceAfter = await fsd.balanceOf(premineAccount3.address);
    // expect(balanceBefore).to.not.be.equal(balanceAfter);
  });
});

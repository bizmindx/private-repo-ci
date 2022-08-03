import { expect } from "chai";
import { ethers } from "hardhat";
import fsdContractsDeployer from "../../helpers/test.deployer";

describe("FSDMinter", () => {
  // Accounts
  let owner;

  // Malicious
  let random;

  let minter;
  let fsd;

  before(async () => {
    [owner, random] = await ethers.getSigners();

    ({ fsd, minter } = await fsdContractsDeployer(owner));
  });

  context("If 'unAuthorized'(non Owner)", () => {
    it("should fail to advance the phase", async () => {
      await expect(fsd.connect(random).phaseAdvance()).to.be.reverted;
      // await expect(fsd.currentPhase()).to.equals(0);
    });

    it("should fail to call updateCurrentPhase", async () => {
      // only owner can advance the phase
      await expect(fsd.connect(random).updateCurrentPhase()).to.be.reverted;
    });
    it("should fail to Mint during 'VCWL' minting ", async () => {
      await expect(minter.connect(random).mintVCWL([], 1000)).to.be.reverted;
    });
    it("should fail to Mint during 'Premine' minting ", async () => {
      await expect(minter.connect(random).mintPremine([], 1000)).to.be.reverted;
    });
    it("should fail to Mint during 'PremineUs' minting ", async () => {
      await expect(
        minter.connect(random).mintPremineUS([random.address], [1000])
      ).to.be.reverted;
    });
    it("should fail to Mint during 'CWL' minting ", async () => {
      await expect(minter.connect(random).mintPremine([random.address], [1000]))
        .to.be.reverted;
    });
    it("should fail if mintToCWL is called ", async () => {
      await expect(minter.connect(random).mintToCWL([], 1000)).to.be.reverted;
    });
    it("should fail if 'mintToFinal' is called ", async () => {
      await expect(minter.connect(random).mintToFinal(random.address, 1000)).to
        .be.reverted;
    });

    it("should fail if 'mint' is called ", async () => {
      await expect(minter.connect(random).mint(1000)).to.be.reverted;
    });
    it("should fail when 'pullTokens' is called  ", async () => {
      await expect(
        minter.connect(random).pullTokensPremine([random.address], [], [1000])
      ).to.be.reverted;
    });
    it("should fail when 'setVestingFactory' is called  ", async () => {
      await expect(minter.connect(random).setVestingFactory(random.address)).to
        .be.reverted;
    });
  });
});

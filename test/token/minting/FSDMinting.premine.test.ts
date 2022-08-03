import { expect } from "chai";
import { ethers } from "hardhat";
import fsdContractsDeployer from "../../helpers/test.deployer";

describe("Premine Minting", () => {
  let owner;
  // Premine
  let premineAccount1;
  let premineAccount2;
  let premineAccount3;
  let premineAccount4;
  let premineAccount5;
  let premineAccount6;

  // Malicious
  let random;
  let fsd;
  let vestingFactory;
  let vestingPRE;
  let minter;

  before(async () => {
    [
      owner,
      premineAccount1,
      premineAccount2,
      premineAccount3,
      premineAccount4,
      premineAccount5,
      premineAccount6,
      random,
    ] = await ethers.getSigners();

    ({ fsd, vestingFactory, vestingPRE, minter } = await fsdContractsDeployer(
      owner
    ));
  });

  it("should mint the premine ", async () => {
    // set the starting implementation
    await vestingFactory.setImplementation(vestingPRE.address);

    await expect(
      vestingFactory.connect(random).setImplementation(random.address)
    ).to.be.reverted;

    // mint premine
    await minter.mintPremine(
      [
        premineAccount1.address,
        premineAccount2.address,
        premineAccount3.address,
        premineAccount4.address,
        premineAccount5.address,
      ],
      [1100000, 1100000, 1100000, 1100000, 1100000]
    );
    it("should not allow non owner account to mint premine", async () => {
      // only owner can mint the premine
      await expect(
        minter.connect(random).mintPremine([random.address], [1000000000])
      ).to.be.reverted;
    });
  });

  it("should check if user got the tokens from the premine", async () => {
    // get user vesting and make sure is the right one
    const userVesting = await minter.userVesting(premineAccount1.address);
    expect(await fsd.balanceOf(userVesting)).to.equal(1100000);
  });

  it("should not allow user to claim tokens from vesting", async () => {
    const userVesting = await minter.userVesting(premineAccount2.address);
    // get user contract vesting
    const userVestingContract = vestingPRE.attach(userVesting);

    // try to get tokens -> should fail
    await expect(
      userVestingContract.connect(premineAccount2).claimVestedTokens()
    ).to.be.revertedWith(
      "FSDVesting::claimVestedTokens: Zero claimable tokens"
    );
  });

  it("should check vestingPRE schedule", async () => {
    vestingPRE = await ethers.getContractFactory("FSDVestingPRE");
    const v = vestingPRE.attach(
      await minter.userVesting(premineAccount1.address)
    );
    expect(await v.calculateVestingClaim()).to.be.equal(0);

    const amount = await v.unclaimedTokens();
    await ethers.provider.send("evm_increaseTime", [12 * 30 * 24 * 60 * 60]); // increase time by 12 months
    await ethers.provider.send("evm_mine", []);

    const fivePercent = amount.mul(5).div(100);
    expect(await v.calculateVestingClaim()).to.be.equal(fivePercent);

    new Array(18).fill(0).forEach(async (_, idx) => {
      await ethers.provider.send("evm_increaseTime", [
        (idx + 1) * 30 * 24 * 60 * 60,
      ]); // increase time by 6 months
      await ethers.provider.send("evm_mine", []);

      expect(await v.calculateVestingClaim()).to.be.equal(
        fivePercent.add(
          amount
            .sub(fivePercent)
            .mul(idx + 1)
            .div(18)
        )
      );
    });

    //TODO fix this
    // expect(await v.unclaimedTokens()).to.be.equal(amount);
    // await v.connect(premineAccount1).claimVestedTokens();
    // expect(await v.unclaimedTokens()).to.be.equal(0);
  });

  it("should mint the US premine", async () => {
    // mint the for us premine and make sure tokens are minted
    await minter.mintPremineUS([premineAccount6.address], [55000000]);
    expect(await fsd.balanceOf(premineAccount6.address)).to.equal(55000000);

    // only owner can mint the premine US
    await expect(
      minter.connect(random).mintPremineUS([random.address], [1000000000])
    ).to.be.reverted;

    // Check the script as we mint direct here
  });
});

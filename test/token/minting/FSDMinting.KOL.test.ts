import { expect } from "chai";
import { ethers } from "hardhat";
import fsdContractsDeployer from "../../helpers/test.deployer";

describe("KOL Minting", () => {
  let owner;
  // Accounts
  let premineAccount;
  // Malicious
  let random;
  let fsd;
  let vestingFactory;
  let vestingKOL;
  let minter;
  before(async () => {
    [owner, premineAccount, random] = await ethers.getSigners();

    ({ fsd, vestingFactory, vestingKOL, minter } = await fsdContractsDeployer(
      owner
    ));
  });

  it("should not allow a non owner account to mint premine", async () => {
    // change the phase to KOL
    await fsd.phaseAdvance();
    // only owner can advance the phase
    await vestingFactory.setImplementation(vestingKOL.address);
    // only owner can mint the premine
    await expect(
      minter.connect(random).mintPremine([random.address], [1000000000])
    ).to.be.reverted;
  });
  it("should mint the KOL and check allocations", async () => {
    // mint tokens
    await minter.mintPremine([premineAccount.address], [20000000]);

    // get user vesting and check if it is right
    const userVesting = await minter.userVesting(premineAccount.address);
    expect(await fsd.balanceOf(userVesting)).to.be.equal(20000000);
  });

  it("should not allow user to withdraw from the vesting contract", async () => {
    const userVesting = await minter.userVesting(premineAccount.address);

    const userVestingContract = vestingKOL.attach(userVesting);

    // try to claim tokens -> should fail
    await expect(
      userVestingContract.connect(premineAccount).claimVestedTokens()
    ).to.be.revertedWith(
      "FSDVesting::claimVestedTokens: Zero claimable tokens"
    );
  });

  it("should check vestingKOL schedule", async () => {
    const v = vestingKOL.attach(
      await minter.userVesting(premineAccount.address)
    );

    expect(await v.calculateVestingClaim()).to.be.equal(0);
    const amount = await v.unclaimedTokens();
    await ethers.provider.send("evm_increaseTime", [12 * 30 * 24 * 60 * 60]); // increase time by 12 months
    await ethers.provider.send("evm_mine", []);

    expect(await v.calculateVestingClaim()).to.be.equal(amount);

    // expect(await v.unclaimedTokens()).to.be.equal(amount);
    // await v.connect(premineAccount).claimVestedTokens();
    // expect(await v.unclaimedTokens()).to.be.equal(0);
  });
});

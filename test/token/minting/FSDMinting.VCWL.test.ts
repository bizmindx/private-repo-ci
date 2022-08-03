import { ZERO_ADDRESS } from "@openzeppelin/test-helpers/src/constants";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SIGNER_ACCOUNT } from "../../helpers/base";
import fsdContractsDeployer from "../../helpers/test.deployer";
import signEIP712Message from "../../helpers/eip712sign";

describe("VCWL Minting", () => {
  let owner;
  // Malicious
  let random;

  // VC Accounts
  let vcAccount1;
  let vcAccount2;
  let vcAccount3;

  let fsd;
  let vestingFactory;
  let vestingVC;
  let minter;

  before(async () => {
    [owner, random, vcAccount1, vcAccount2, vcAccount3] =
      await ethers.getSigners();

    ({ fsd, vestingFactory, vestingVC, minter } = await fsdContractsDeployer(
      owner
    ));
    //advance phase to VCWL minting
    await fsd.updateCurrentPhase(2);
  });
  it("should not allow to mint from a non whitelisted account", async () => {
    await vestingFactory.setImplementation(vestingVC.address);

    // try to mint from a non whitelisted account
    await expect(
      minter.connect(random).mintVCWL(random.address, 1000000, {
        value: ethers.utils.parseEther("500"),
      })
    ).to.be.reverted;
  });
  it("should mint the VCWL", async () => {
    // create signatures for vc1, vc2 and v3 and mint FSD
    const signatureVc1 = signEIP712Message(
      minter.address,
      vcAccount1.address,
      SIGNER_ACCOUNT.privateKey
    );
    await minter.connect(vcAccount1).mintVCWL(signatureVc1, 1000000, {
      value: ethers.utils.parseEther("500"),
    });
    const userVesting = await minter.userVesting(vcAccount1.address);
    expect(userVesting).to.not.be.equal(ZERO_ADDRESS);

    const signatureVc2 = signEIP712Message(
      minter.address,
      vcAccount2.address,
      SIGNER_ACCOUNT.privateKey
    );
    await minter.connect(vcAccount2).mintVCWL(signatureVc2, 1000000, {
      value: ethers.utils.parseEther("500"),
    });
    const userVesting2 = await minter.userVesting(vcAccount2.address);
    expect(userVesting2).to.not.be.equal(ZERO_ADDRESS);

    const signatureVc3 = signEIP712Message(
      minter.address,
      vcAccount3.address,
      SIGNER_ACCOUNT.privateKey
    );
    await minter.connect(vcAccount3).mintVCWL(signatureVc3, 1000000, {
      value: ethers.utils.parseEther("500"),
    });
    const userVesting3 = await minter.userVesting(vcAccount2.address);
    expect(userVesting3).to.not.be.equal(ZERO_ADDRESS);
  });

  it("should check FSDVestingVC schedule", async () => {
    const v = vestingVC.attach(await minter.userVesting(vcAccount2.address));
    expect(await v.calculateVestingClaim()).to.be.equal(0);

    const amount = await v.amount();
    await ethers.provider.send("evm_increaseTime", [12 * 30 * 24 * 60 * 60]); // increase time by 12 months
    await ethers.provider.send("evm_mine", []);

    const fivePercent = amount
      .mul(ethers.BigNumber.from(5))
      .div(ethers.BigNumber.from(100));

    const deviance = ethers.utils.parseEther("1");

    expect(await v.calculateVestingClaim()).to.be.lt(fivePercent.add(deviance));

    expect(await v.calculateVestingClaim()).to.be.gt(fivePercent.sub(deviance));

    new Array(12).fill(0).reduce(async (_, idx) => {
      await ethers.provider.send("evm_increaseTime", [
        (idx + 1) * 30 * 24 * 60 * 60,
      ]); // increase time by 6 months
      await ethers.provider.send("evm_mine", []);

      expect(await v.calculateVestingClaim()).to.be.lt(
        fivePercent
          .add(
            amount
              .sub(fivePercent)
              .mul(ethers.BigNumber.from(idx + 1))
              .div(ethers.BigNumber.from(12))
          )
          .add(deviance)
      );

      expect(await v.calculateVestingClaim()).to.be.gt(
        fivePercent
          .add(
            amount
              .sub(fivePercent)
              .mul(ethers.BigNumber.from(idx + 1))
              .div(ethers.BigNumber.from(12))
          )
          .sub(deviance)
      );
    }, null);

    // expect(await v.unclaimedTokens()).to.be.equal(amount);
    // await v.connect(premineAccount1).claimVestedTokens();
    // expect(await v.unclaimedTokens()).to.be.equal(0);
  });

  // it("should buy FSD with DAI", async () => {
  //   const {
  //     data: {
  //       tx: { data, to },
  //       toTokenAmount,
  //     },
  //   } = await axios.get(
  //     "https://api.1inch.io/v4.0/1/swap?" +
  //       "fromTokenAddress=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" +
  //       "&toTokenAddress=0x6B175474E89094C44Da98b954EedeAC495271d0F" +
  //       "&amount=" +
  //       ethers.utils.parseEther("10") +
  //       "&fromAddress=" +
  //       vcAccount1.address +
  //       "&slippage=10&disableEstimate=true"
  //   );

  //   await vcAccount1.sendTransaction({
  //     to,
  //     data,
  //     value: ethers.utils.parseEther("10"),
  //   });

  //   const dai = new ethers.Contract(
  //     "0x6B175474E89094C44Da98b954EedeAC495271d0F",
  //     daiABI,
  //     vcAccount1
  //   );

  //   expect(await dai.balanceOf(vcAccount1.address)).to.not.be.equal(0);
  // });
});

import { ZERO_ADDRESS } from "@openzeppelin/test-helpers/src/constants";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SIGNER_ACCOUNT } from "../../helpers/base";
import fsdContractsDeployer from "../../helpers/test.deployer";
import signEIP712Message from "../../helpers/eip712sign";

describe("CWL Minting", () => {
  let owner;
  // Malicious
  let nonWhitelist;

  // CW Accounts
  let cwAccount1;
  let cwAccount2;
  let cwAccount3;
  let fsd;
  let vestingKOL;
  let minter;

  before(async () => {
    [owner, nonWhitelist, cwAccount1, cwAccount2, cwAccount3] =
      await ethers.getSigners();

    ({ fsd, minter, vestingKOL } = await fsdContractsDeployer(owner));
  });

  it("should not allow to mint from a non whitelisted account", async () => {
    // try to mint from a non whitelisted account
    await expect(
      minter.connect(nonWhitelist).mintCWL(nonWhitelist.address, 1000000, {
        value: ethers.utils.parseEther("500"),
      })
    ).to.be.reverted;
  });
  it("should mint the CWL", async () => {
    await fsd.updateCurrentPhase(3);
    // create signatures for cw1, cw2 and cw3 and mint FSD
    const signatureCW1 = signEIP712Message(
      minter.address,
      cwAccount1.address,
      SIGNER_ACCOUNT.privateKey
    );
    await minter
      .connect(cwAccount1)
      .mintCWL(signatureCW1, 1000000, { value: ethers.utils.parseEther("10") });
    const userVesting = vestingKOL.attach(
      await minter.userVesting(cwAccount1.address)
    );

    expect(userVesting).to.not.be.equal(ZERO_ADDRESS);

    const signatureCW2 = signEIP712Message(
      minter.address,
      cwAccount2.address,
      SIGNER_ACCOUNT.privateKey
    );
    await minter
      .connect(cwAccount2)
      .mintCWL(signatureCW2, 1000000, { value: ethers.utils.parseEther("10") });
    const userVesting2 = vestingKOL.attach(
      await minter.userVesting(cwAccount2.address)
    );

    expect(userVesting2).to.not.be.equal(ZERO_ADDRESS);

    const signatureCW3 = signEIP712Message(
      minter.address,
      cwAccount3.address,
      SIGNER_ACCOUNT.privateKey
    );
    await minter
      .connect(cwAccount3)
      .mintCWL(signatureCW3, 1000000, { value: ethers.utils.parseEther("10") });
    const userVesting3 = vestingKOL.attach(
      await minter.userVesting(cwAccount3.address)
    );

    //TODO add more checks here
    expect(userVesting3).to.not.be.equal(ZERO_ADDRESS);
  });
});

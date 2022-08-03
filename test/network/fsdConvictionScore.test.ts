import { FairSideConviction, FSD, FSDMinter, FSDNetwork } from "../../typechain-types";
import { ethers } from "hardhat";
import fsdContractsDeployer from "../helpers/test.deployer";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {expect} from "chai";
import {BigNumber} from "ethers";

const provider = ethers.provider;

function increaseTime (seconds) {
  ethers.provider.send('evm_increaseTime', [seconds])
  ethers.provider.send('evm_mine', [])
}

function toFixed(num, fixed) {
  const re = new RegExp('^-?\\d+(?:\.\\d{0,' + (fixed || -1) + '})?');
  return Number(num.toString().match(re)[0]);
}


function toUnits(balance: any) {
  return toFixed(ethers.utils.formatEther(balance), 4);
}

const exp = BigNumber.from(10).pow(18)

async function advancePhases(fsd: FSD) {
  // Advance phases
  await fsd.phaseAdvance(); // Premine > KOL
  await fsd.phaseAdvance(); // KOL > VCWL
  await fsd.phaseAdvance(); // KOL > VCWL
  await fsd.phaseAdvance(); // CWL > Final
}

describe.only("FSD Testing conviction scores", () => {


  let owner: SignerWithAddress;

  let fsd: FSD;
  let minter: FSDMinter;
  let fsdNetwork: FSDNetwork;
  let conviction: FairSideConviction;
  let accounts:any[]

  const mintValue = ethers.utils.parseEther("990");
  before(async () => {
    accounts = await ethers.getSigners();
    owner = accounts[0];

    ({ fsd, fsdNetwork, minter, conviction } = await fsdContractsDeployer(
        owner
    ));

    // Admin: Funding convictions
    await fsd.fundConvictions(exp.mul(1_000_000_000))

    //add funds to the capital pool to cover membership costs
    for (const account of accounts) {
      const tx = await account.sendTransaction({
        to: fsd.address,
        value: mintValue,
      });
    }

    const balance = await provider.getBalance(fsd.address);
    console.info(`Capital Pool balance: ${(toUnits(balance))} ETH`)



  });

  it("Test FSD conviction score scenarios", async () => {
    await advancePhases(fsd);

    const [clark, jack, alice, jenny] = accounts.slice(1, 5);

    await minter.connect(clark).mint(0, {value: mintValue});
    await minter.connect(jack).mint(0, {value: mintValue});
    await minter.connect(alice).mint(0, {value: mintValue});


    // Start acquiring convictions
    await expect(fsd.connect(clark).startAcquireConviction()).to.emit(fsd, "ConvictionAccumulationStarted");
    await expect(fsd.connect(jack).startAcquireConviction()).to.emit(fsd, "ConvictionAccumulationStarted");
    await expect(fsd.connect(alice).startAcquireConviction()).to.emit(fsd, "ConvictionAccumulationStarted");
    await expect(fsd.connect(jenny).startAcquireConviction()).to.emit(fsd, "ConvictionAccumulationStarted");

    // Jenny never minted or hold any FSD at this point, so we expect his conviction to be 0
    expect(await fsd.getConvictionScore(jenny.address)).to.equal(0)
    expect(await fsd.balanceOf(jenny.address)).to.equal(0)


    // Clark and others have started accruing some conviction scores value since they minted FSD
    // And have been holding for a few blocks now
    expect(toUnits(await fsd.getConvictionScore(clark.address))).to.be.equal(3.7976)
    expect(toUnits(await fsd.balanceOf(clark.address))).to.be.equal(16428.0411)

    expect(toUnits(await fsd.getConvictionScore(jack.address))).to.be.equal(3.2649)
    expect(toUnits(await fsd.balanceOf(jack.address))).to.be.equal(14123.9794)

    expect(toUnits(await fsd.getConvictionScore(alice.address))).to.be.equal(2.7674)
    expect(toUnits(await fsd.balanceOf(alice.address))).to.be.equal(11971.5672)

    /// Test total conviction at the current time
    expect(toUnits(await fsd.getTotalAvailableConviction())).to.be.equal(14.2694)

    /// Jack sends all his FSD to Jenny
    await fsd.connect(jack).transfer(jenny.address, await fsd.balanceOf(jack.address))

    /// 10 days later
    await increaseTime(10 * 86400)

    /// Since Jack sold all his FSD, his conviction score never increased since then, in fact it reduced
    expect(toUnits(await fsd.getConvictionScore(jack.address))).to.be.equal( 3.0543)

    /// On the other hand Jenny conviction accrued in the past 10 days, since he's been holding since then
    expect(toUnits(await fsd.getConvictionScore(jenny.address))).to.be.equal(90998.6221)
    expect(toUnits(await fsd.balanceOf(jenny.address))).to.be.equal(14123.9794)


    /// A year later, the convictions of long time holders should have accrued significantly
    await increaseTime(365 * 86400)

    expect(toUnits(await fsd.getConvictionScore(clark.address))).to.be.equal(3969124.4277)
    expect(toUnits(await fsd.balanceOf(clark.address))).to.be.equal(16428.0411)

    expect(toUnits(await fsd.getConvictionScore(alice.address))).to.be.equal(2892410.5716)
    expect(toUnits(await fsd.balanceOf(alice.address))).to.be.equal(11971.5672)

  });

});

const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { signEIP712Message } = require("../helpers/eip712sign");
const { createPoolNewAddress, SIGNER_ACCOUNT, advanceBlocks } = require("../helpers/base");

describe("VCWL Minting", () => {
    // Accounts
    let owner;

    // Premine
    let premineAcc1;
    let premineAcc2;
    let premineAcc3;
    let premineAcc4;
    let premineAcc5;
    let premineAcc6;
    let premineAcc7;

    // Malicious
    let random;

    // VC Accounts
    let vcAcc1;
    let vcAcc2;
    let vcAcc3;

    // CW Accounts
    let cwAcc1;
    let cwAcc2;
    let cwAcc3;

    let membershipBuyer1;

    let fundingPool;
    let premiumsPool;

    let timelock;

    let fsd;

    let formula;

    let conviction;

    let dao;

    let vestingFactory;

    let vestingPRE;
    let vestingKOL;
    let vestingVC;

    let minter;

    let fsdNetwork;

    before(async () => {
        [
            owner,
            premineAcc1,
            premineAcc2,
            premineAcc3,
            premineAcc4,
            premineAcc5,
            premineAcc6,
            premineAcc7,
            random,
            vcAcc1,
            vcAcc2,
            vcAcc3,
            cwAcc1,
            cwAcc2,
            cwAcc3,
            membershipBuyer1,
        ] = await ethers.getSigners(16);

        fundingPool = createPoolNewAddress();
        premiumsPool = createPoolNewAddress();

        // deploy timelock
        timelock = await ethers.getContractFactory("Timelock");
        timelock = await timelock.deploy(owner.address, 360000);

        expect(timelock.address).to.not.equal(ZERO_ADDRESS);

        // deploy FSD
        formula = await ethers.getContractFactory("FairSideFormula");
        formula = await formula.deploy();

        expect(formula.address).to.not.equal(ZERO_ADDRESS);

        fsd = await ethers.getContractFactory("FSD", {
            libraries: {
                FairSideFormula: formula.address,
            },
        });
        fsd = await fsd.deploy(fundingPool, timelock.address);

        expect(fsd.address).to.not.equal(ZERO_ADDRESS);

        // deploy NFT
        conviction = await ethers.getContractFactory("FairSideConviction");
        conviction = await conviction.deploy(fsd.address);

        expect(conviction.address).to.not.equal(ZERO_ADDRESS);

        // deploy DAO
        dao = await ethers.getContractFactory("FairSideDAO");
        dao = await dao.deploy(timelock.address, fsd.address, owner.address);

        expect(dao.address).to.not.equal(ZERO_ADDRESS);

        // deploy Minter
        minter = await ethers.getContractFactory("FSDMinter");
        minter = await minter.deploy(fsd.address, SIGNER_ACCOUNT.publicKey);

        expect(minter.address).to.not.equal(ZERO_ADDRESS);

        // deploy Vesting factory
        vestingFactory = await ethers.getContractFactory("FSDVestingFactory");
        vestingFactory = await vestingFactory.deploy(minter.address);

        expect(vestingFactory.address).to.not.equal(ZERO_ADDRESS);

        // set the vesting factory on minter
        await minter.setVestingFactory(vestingFactory.address);

        // deploy Network
        fsdNetwork = await ethers.getContractFactory("FSDNetwork", {
            libraries: {
                FairSideFormula: formula.address,
            },
        });
        fsdNetwork = await fsdNetwork.deploy(
            fsd.address,
            fundingPool,
            premiumsPool,
            owner.address,
            timelock.address
        );

        expect(fsdNetwork.address).to.not.equal(ZERO_ADDRESS);

        await fsd.connect(owner).setFairSideConviction(conviction.address);

        await fsd.connect(owner).setFairSideNetwork(fsdNetwork.address);

        await fsd.connect(owner).setMinter(minter.address);

        await fsdNetwork.connect(owner).setCsrTypes(155, true);

        // deploy Vesting PRE
        vestingPRE = await ethers.getContractFactory("FSDVestingPRE");
        vestingPRE = await vestingPRE.deploy(
            fsd.address,
            vestingFactory.address,
            minter.address,
            dao.address,
            conviction.address
        );

        expect(vestingPRE.address).to.not.equal(ZERO_ADDRESS);

        // deploy Vesting KOL
        vestingKOL = await ethers.getContractFactory("FSDVestingKOL");
        vestingKOL = await vestingKOL.deploy(
            fsd.address,
            vestingFactory.address,
            minter.address,
            dao.address,
            conviction.address
        );

        // deploy Vesting VC
        expect(vestingKOL.address).to.not.equal(ZERO_ADDRESS);

        vestingVC = await ethers.getContractFactory("FSDVestingVC");
        vestingVC = await vestingVC.deploy(
            fsd.address,
            vestingFactory.address,
            minter.address,
            dao.address,
            conviction.address
        );

        expect(vestingVC.address).to.not.equal(ZERO_ADDRESS);
    });
    it("should not allow to mint from a non whitelisted account", async () => {
        await fsd.phaseAdvance();
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
        const sigVc1 = signEIP712Message(
            minter.address,
            vcAcc1.address,
            SIGNER_ACCOUNT.privateKey
        );
        await minter
            .connect(vcAcc1)
            .mintVCWL(sigVc1, 1000000, { value: ethers.utils.parseEther("500") });
        const userVesting = await minter.userVesting(vcAcc1.address);
        expect(userVesting).to.not.be.equal(ZERO_ADDRESS);

        const sigVc2 = signEIP712Message(
            minter.address,
            vcAcc2.address,
            SIGNER_ACCOUNT.privateKey
        );
        await minter
            .connect(vcAcc2)
            .mintVCWL(sigVc2, 1000000, { value: ethers.utils.parseEther("500") });
        const userVesting2 = await minter.userVesting(vcAcc2.address);
        expect(userVesting2).to.not.be.equal(ZERO_ADDRESS);

        const sigVc3 = signEIP712Message(
            minter.address,
            vcAcc3.address,
            SIGNER_ACCOUNT.privateKey
        );
        await minter
            .connect(vcAcc3)
            .mintVCWL(sigVc3, 1000000, { value: ethers.utils.parseEther("500") });
        const userVesting3 = await minter.userVesting(vcAcc2.address);
        expect(userVesting3).to.not.be.equal(ZERO_ADDRESS);
    });

    it("should check FSDVestingVC schedule", async () => {
        const v = vestingVC.attach(await minter.userVesting(vcAcc2.address));
        expect(await v.calculateVestingClaim()).to.be.equal(0);

        const amount = await v.amount();
        await ethers.provider.send("evm_increaseTime", [12 * 30 * 24 * 60 * 60]); // increase time by 12 months
        await ethers.provider.send("evm_mine");

        const fivePercent = amount
            .mul(ethers.BigNumber.from(5))
            .div(ethers.BigNumber.from(100));

        const deviance = ethers.utils.parseEther("1");

        expect(await v.calculateVestingClaim()).to.be.lt(
            fivePercent.add(deviance)
        );

        expect(await v.calculateVestingClaim()).to.be.gt(
            fivePercent.sub(deviance)
        );

        new Array(12).fill(0).reduce(async (_, idx) => {
            await ethers.provider.send("evm_increaseTime", [
                (idx + 1) * 30 * 24 * 60 * 60,
            ]); // increase time by 6 months
            await ethers.provider.send("evm_mine");

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
        // await v.connect(premineAcc1).claimVestedTokens();
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
    //       vcAcc1.address +
    //       "&slippage=10&disableEstimate=true"
    //   );

    //   await vcAcc1.sendTransaction({
    //     to,
    //     data,
    //     value: ethers.utils.parseEther("10"),
    //   });

    //   const dai = new ethers.Contract(
    //     "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    //     daiABI,
    //     vcAcc1
    //   );

    //   expect(await dai.balanceOf(vcAcc1.address)).to.not.be.equal(0);
    // });
});

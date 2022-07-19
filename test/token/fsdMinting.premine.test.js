const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { signEIP712Message } = require("../helpers/eip712sign");
const { createPoolNewAddress, SIGNER_ACCOUNT, advanceBlocks } = require("../helpers/base");

const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const { default: axios } = require("axios");

describe("Premine Minting", () => {
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

    it("should mint the premine ", async () => {
        // set the starting implementation
        await vestingFactory.setImplementation(vestingPRE.address);

        await expect(
            vestingFactory.connect(random).setImplementation(random.address)
        ).to.be.reverted;

        // mint premine
        await minter.mintPremine(
            [
                premineAcc1.address,
                premineAcc2.address,
                premineAcc3.address,
                premineAcc4.address,
                premineAcc5.address,
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
        const userVesting = await minter.userVesting(premineAcc1.address);
        expect(await fsd.balanceOf(userVesting)).to.equal(1100000);
    });

    it("should not allow user to claim tokens from vesting", async () => {
        const userVesting = await minter.userVesting(premineAcc2.address);
        // get user contract vesting
        const userVestingContract = vestingPRE.attach(userVesting);

        // try to get tokens -> should fail
        await expect(
            userVestingContract.connect(premineAcc2).claimVestedTokens()
        ).to.be.revertedWith(
            "FSDVesting::claimVestedTokens: Zero claimable tokens"
        );
    });

    it("should check vestingPRE schedule", async () => {
        vestingPRE = await ethers.getContractFactory("FSDVestingPRE");
        const v = vestingPRE.attach(
            await minter.userVesting(premineAcc1.address)
        );
        expect(await v.calculateVestingClaim()).to.be.equal(0);

        const amount = await v.unclaimedTokens();
        await ethers.provider.send("evm_increaseTime", [12 * 30 * 24 * 60 * 60]); // increase time by 12 months
        await ethers.provider.send("evm_mine");

        const fivePercent = amount.mul(5).div(100);
        expect(await v.calculateVestingClaim()).to.be.equal(fivePercent);

        new Array(18).fill(0).forEach(async (_, idx) => {
            await ethers.provider.send("evm_increaseTime", [
                (idx + 1) * 30 * 24 * 60 * 60,
            ]); // increase time by 6 months
            await ethers.provider.send("evm_mine");

            expect(await v.calculateVestingClaim()).to.be.equal(
                fivePercent.add(
                    amount
                        .sub(fivePercent)
                        .mul(idx + 1)
                        .div(18)
                )
            );
        });

        // expect(await v.unclaimedTokens()).to.be.equal(amount);
        // await v.connect(premineAcc1).claimVestedTokens();
        // expect(await v.unclaimedTokens()).to.be.equal(0);
    });

    it("should mint the US premine", async () => {
        // mint the for us premine and make sure tokens are minted
        await minter.mintPremineUS([premineAcc6.address], [55000000]);
        expect(await fsd.balanceOf(premineAcc6.address)).to.equal(55000000);

        // only owner can mint the premine US
        await expect(
            minter.connect(random).mintPremineUS([random.address], [1000000000])
        ).to.be.reverted;

        // Check the script as we mint direct here
    });
});
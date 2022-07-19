const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { createPoolNewAddress, SIGNER_ACCOUNT } = require("../helpers/base");



describe("FSDToken", () => {
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
        // make sure that we are handling governance
        expect(await fsd.isGovernance(premineAcc2.address)).to.be.equal(true);
        expect(await fsd.isGovernance(membershipBuyer1.address)).to.be.equal(
            true
        );
        expect(await fsd.isGovernance(premineAcc4.address)).to.be.equal(false);
        expect(await fsd.isGovernance(random.address)).to.be.equal(false);
    });
    it("should burn FSD for ETH", async () => {
        const balanceBefore = await fsd.balanceOf(premineAcc5.address);
        await fsd.connect(premineAcc5).burn(10, 10000);
        const balanceAfter = await fsd.balanceOf(premineAcc5.address);
        expect(balanceBefore).to.not.be.equal(balanceAfter);
    });
});
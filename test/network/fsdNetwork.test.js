const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { signEIP712Message } = require("../helpers/eip712sign");
const { createPoolNewAddress, SIGNER_ACCOUNT, advanceBlocks } = require("../helpers/base");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const { default: axios } = require("axios");


describe("FSDNetwork", () => {
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

    it("should fail to purchase membership with 0.3 eth", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .purchaseMembershipETH({ value: ethers.utils.parseEther("0.3") })
        ).to.be.revertedWith(
            "FSDNetwork::purchaseMembershipETH: Invalid cost share benefit specified"
        );
    });
    it("should fail to to purchase membership with 1000 eth", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .purchaseMembershipETH({ value: ethers.utils.parseEther("1000") })
        ).to.be.revertedWith(
            "FSDNetwork::purchaseMembershipETH: Exceeds cost share benefit limit per account"
        );
    });
    it("should fail to purchase membership with 1 eth when there is no capital to cover it", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .purchaseMembershipETH({ value: ethers.utils.parseEther("1") })
        ).to.be.revertedWith(
            "FSDNetwork::purchaseMembershipETH: Insufficient Capital to Cover Membership"
        );
    });

    it("should fail to open a cost share request with 0.3 eth", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .openCostShareRequest(ethers.utils.parseEther("0.3"), false, 155)
        ).to.be.revertedWith(
            "FSDNetwork::openCostShareRequest: Ineligible cost share request"
        );
    });

    it("should fail to update a cost share request with a invalid signature", async () => {
        await expect(
            fsdNetwork.connect(random).updateCostShareRequest(0, 1, 0, 0)
        ).to.be.revertedWith("ECDSA: invalid signature length");
    });

    it("should fail to add to staking rewards from a non whilelisted account", async () => {
        await expect(
            fsdNetwork.connect(random).addStakingReward(1000)
        ).to.be.revertedWith(
            "FSDNetwork::addStakingReward: Insufficient Privileges"
        );
    });

    it("should fail to try to set assesors from a random account", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .setAssessors([random.address, random.address, random.address])
        ).to.be.revertedWith("FSDNetwork::setAssessors: Insufficient Privileges");
    });

    it("should fail to try to set crs types from a random account", async () => {
        await expect(
            fsdNetwork.connect(random).setCsrTypes(911, true)
        ).to.be.revertedWith("FSDNetwork::setDataEntry: Insufficient Privileges");
    });

    it("should fail to set membership wallets after membership expiry", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .setMembershipWallets([ZERO_ADDRESS, random.address])
        ).to.be.revertedWith(
            "FSDNetwork::setMembershipWallets: Membership expired"
        );
    });

    it("should fail to set membership wallets when wallets not unique", async () => {
        await expect(
            fsdNetwork
                .connect(random)
                .setMembershipWallets([random.address, random.address])
        ).to.be.revertedWith(
            "FSDNetwork::setMembershipWallets: Membership expired"
        );
    });
    it("should fail to add more than 3 wallets for member", async () => {

        await expect(
            fsdNetwork
                .connect(random)
                .setMembershipWallets([vcAcc1.address, vcAcc2.address])
        ).to.be.revertedWith(
            "FSDNetwork::setMembershipWallets: Membership expired"
        );
    });

    it("should fail to set the slippage tolerance from a random account", async () => {
        await expect(
            fsdNetwork.connect(random).setSlippageTolerance(100)
        ).to.be.revertedWith("FSDNetwork:: Insufficient Privileges");
    });

    it("should fail to set the membership fee from a random account", async () => {
        await expect(
            fsdNetwork.connect(random).setMembershipFee(100)
        ).to.be.revertedWith("FSDNetwork:: Insufficient Privileges");
    });

    it("should fail to set the gearing factor from a random account", async () => {
        await expect(
            fsdNetwork.connect(random).setGearingFactor(100)
        ).to.be.revertedWith("FSDNetwork:: Insufficient Privileges");
    });

    it("should fail to set the gearing factor from a incorect value", async () => {
        await expect(fsdNetwork.setGearingFactor(0)).to.be.revertedWith(
            "FSDNetwork::setGearingFactor: Incorrect Value Specified"
        );
    });

    it("should fail to set the gearing factor", async () => {
        await expect(fsdNetwork.setGearingFactor(1)).to.be.revertedWith(
            "FSDNetwork::setGearingFactor: Cannot change"
        );
    });
    it("should deposit more than 4000 ETH", async () => {
        // console.log('this is the balance in minter', minter)
        await minter.connect(premineAcc5).mint(1, {
            value: ethers.utils.parseEther("4000"),
        });

        await minter.connect(premineAcc4).mint(1, {
            value: ethers.utils.parseEther("100"),
        });
    });

    it("should purchase membership with FSD", async () => {
        await advanceBlocks(5);

        // approve the fsd network contract
        await fsd
            .connect(premineAcc5)
            .approve(fsdNetwork.address, ethers.utils.parseEther("10000000"));

        // purchase membership with FSD
        await fsdNetwork
            .connect(premineAcc5)
            .purchaseMembership(ethers.utils.parseEther("10"));

        // make sure that we the user is getting his position and that the state is updated properly
        expect(await fsdNetwork.membership(premineAcc5.address)).to.not.equal([]);
        expect(await fsdNetwork.totalCostShareBenefits()).to.equal(
            "10000000000000000000"
        );
    });

    it("should purchase membership with ETH", async () => {
        await advanceBlocks(5000);

        const fundingpoolBalance = await ethers.provider.getBalance(fsd.address);

        await minter.connect(membershipBuyer1).mint(1, {
            value: ethers.utils.parseEther("10"),
        });

        await fsd
            .connect(membershipBuyer1)
            .approve(fsdNetwork.address, ethers.utils.parseEther("10000000"));
        await fsdNetwork
            .connect(membershipBuyer1)
            .purchaseMembershipETH({ value: ethers.utils.parseEther("1") });

        const fundingpoolBalanceAfter = await ethers.provider.getBalance(
            fundingPool
        );

        // make sure that we advance the funding pool via deposits
        expect(fundingpoolBalance).to.not.be.equal(fundingpoolBalanceAfter);
    });

    it("should tokenize conviction", async () => {
        // approve the fsd contract
        await fsd
            .connect(premineAcc4)
            .approve(fsd.address, ethers.utils.parseEther("10000000"));

        await fsd.connect(premineAcc4).tokenizeConviction(10);
        const convictionScore = await fsd.checkpoints(premineAcc4.address, 0);
        // console.log(convictionScore);
        //****** TODO: Check why conviction score is 0 even before we tokenize *****/
    });
    it("should open a new cost share request ", async () => {
        // approve the fsd network contract
        await fsd
            .connect(premineAcc5)
            .approve(fsdNetwork.address, ethers.utils.parseEther("10000000"));

        await fsdNetwork
            .connect(premineAcc5)
            .openCostShareRequest(ethers.utils.parseEther("10"), false, 155);
    });
    it("should get the fsd price", async () => {
        let fsdPrice = await fsdNetwork.getFSDPrice();
        let ethPrice = await fsdNetwork.getEtherPrice();
        expect(ethPrice).to.be.not.equal("0");
        expect(fsdPrice).to.be.not.equal("0");
    });
});
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { signEIP712Message } = require("./helpers/eip712sign");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const { default: axios } = require("axios");

describe("FSD", function () {
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

    const SIGNER_ACCOUNT = {
        publicKey: "0xC6C23De51657dd9C2C4F921Ffa66CCFe3C2FbFD9",
        privateKey: Buffer.from(
            "4626faca3179addddacb3cb60ba3fe5b0943d11de9afbded0154b379df7ba5f4",
            "hex"
        ),
    };

    const createPoolNewAddress = () => {
        const addr = web3.eth.accounts.create();
        return web3.utils.toChecksumAddress(addr.address);
    };

    const advanceBlocks = async (numberOfBlocks) => {
        for (let index = 0; index < numberOfBlocks; index++) {
            await ethers.provider.send("evm_increaseTime", [3600]);
            await ethers.provider.send("evm_mine");
        }
    };

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

    describe("Premine Minting", () => {
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

    describe("KOL Minting", () => {
        it("should not allow a non owner account to advance the phase or mint", async () => {
            // change the phase to KOL
            await fsd.phaseAdvance();

            // only owner can advance the phase
            await expect(fsd.connect(random).phaseAdvance()).to.be.reverted;
            await vestingFactory.setImplementation(vestingKOL.address);
            // only owner can mint the premine
            await expect(
                minter.connect(random).mintPremine([random.address], [1000000000])
            ).to.be.reverted;
        });
        it("should mint the KOL and check allocations", async () => {
            // mint tokens
            await minter.mintPremine([premineAcc7.address], [20000000]);

            // get user vesting and check if it is right
            const userVesting = await minter.userVesting(premineAcc7.address);
            expect(await fsd.balanceOf(userVesting)).to.be.equal(20000000);
        });

        it("should not allow user to withdraw from the vesting contract", async () => {
            const userVesting = await minter.userVesting(premineAcc7.address);

            const userVestingContract = vestingKOL.attach(userVesting);

            // try to claim tokens -> should fail
            await expect(
                userVestingContract.connect(premineAcc7).claimVestedTokens()
            ).to.be.revertedWith(
                "FSDVesting::claimVestedTokens: Zero claimable tokens"
            );
        });

        it("should check vestingKOL schedule", async () => {
            const v = vestingKOL.attach(
                await minter.userVesting(premineAcc7.address)
            );

            expect(await v.calculateVestingClaim()).to.be.equal(0);
            const amount = await v.unclaimedTokens();
            await ethers.provider.send("evm_increaseTime", [12 * 30 * 24 * 60 * 60]); // increase time by 12 months
            await ethers.provider.send("evm_mine");

            expect(await v.calculateVestingClaim()).to.be.equal(amount);

            // expect(await v.unclaimedTokens()).to.be.equal(amount);
            // await v.connect(premineAcc1).claimVestedTokens();
            // expect(await v.unclaimedTokens()).to.be.equal(0);
        });
    });

    describe("VCWL Minting", () => {
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

    describe("CWL Minting", () => {
        it("should not allow to mint from a non whitelisted account", async () => {
            await fsd.phaseAdvance();

            // try to mint from a non whitelisted account
            await expect(
                minter.connect(random).mintCWL(random.address, 1000000, {
                    value: ethers.utils.parseEther("500"),
                })
            ).to.be.reverted;
        });
        it("should mint the CWL", async () => {
            // create signatures for cw1, cw2 and cw3 and mint FSD
            const sigCW1 = signEIP712Message(
                minter.address,
                cwAcc1.address,
                SIGNER_ACCOUNT.privateKey
            );
            await minter
                .connect(cwAcc1)
                .mintCWL(sigCW1, 1000000, { value: ethers.utils.parseEther("10") });
            const userVesting = vestingKOL.attach(
                await minter.userVesting(cwAcc1.address)
            );

            expect(userVesting).to.not.be.equal(ZERO_ADDRESS);

            const sigCW2 = signEIP712Message(
                minter.address,
                cwAcc2.address,
                SIGNER_ACCOUNT.privateKey
            );
            await minter
                .connect(cwAcc2)
                .mintCWL(sigCW2, 1000000, { value: ethers.utils.parseEther("10") });
            const userVesting2 = vestingKOL.attach(
                await minter.userVesting(cwAcc2.address)
            );

            expect(userVesting2).to.not.be.equal(ZERO_ADDRESS);

            const sigCW3 = signEIP712Message(
                minter.address,
                cwAcc3.address,
                SIGNER_ACCOUNT.privateKey
            );
            await minter
                .connect(cwAcc3)
                .mintCWL(sigCW3, 1000000, { value: ethers.utils.parseEther("10") });
            const userVesting3 = vestingKOL.attach(
                await minter.userVesting(cwAcc3.address)
            );

            expect(userVesting3).to.not.be.equal(ZERO_ADDRESS);
        });
    });

    describe("Final Minting", () => {
        it("should mint in the final phase", async () => {
            await fsd.phaseAdvance();

            // mint tokens for 1 ether
            await minter.connect(premineAcc1).mint(1, {
                value: ethers.utils.parseEther("1"),
            });

            // make sure we have tokens minted
            expect(await fsd.balanceOf(premineAcc1.address)).to.not.be.equal(0);

            // Make sure that we are splitting 30/70
            expect(await ethers.provider.getBalance(fundingPool)).to.equal(
                ethers.utils.parseEther("459.3")
            );
            expect(await ethers.provider.getBalance(fsd.address)).to.equal(
                ethers.utils.parseEther("1071.7")
            );
        });

        it("should add ETH after the 500 limit to funding pool has achieved and check allocations", async () => {
            // Add 500 Ether to funding pool
            await minter.connect(premineAcc2).mint(1, {
                value: ethers.utils.parseEther("1000"),
            });
            await minter.connect(premineAcc3).mint(1, {
                value: ethers.utils.parseEther("667"),
            });

            const fundingpoolBalance = await ethers.provider.getBalance(fundingPool);

            // make sure we are not collecting anymore for funding pool
            await minter.connect(premineAcc4).mint(1, {
                value: ethers.utils.parseEther("100"),
            });

            expect(await ethers.provider.getBalance(fundingPool)).to.be.equal(
                fundingpoolBalance
            );
            it("should burn FSD for ETH", async () => {
                // try to burn from a bad account
                expect(await fsd.connect(random).burn(0, 10000)).to.be.reverted;
                const balanceBefore = await fsd.balanceOf(premineAcc1.address);
                await fsd.connect(premineAcc1).burn(100, 100);
                const balanceAfter = await fsd.balanceOf(premineAcc1.address);
                expect(balanceBefore).to.not.be.equal(balanceAfter);
            });
        });
    });

    describe("FSDNetwork", () => {
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
            // deposit 4000 ETH and 100 ETH
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
            // TODO: Check why conviction score is 0 even before we tokenize
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

    describe("FSDToken", () => {
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
            expect(await fsd.isGovernance(premineAcc2.address)).to.be.equal(false);
            expect(await fsd.isGovernance(membershipBuyer1.address)).to.be.equal(
                false
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
    describe("FSDMinter", () => {
        it("should evaluate all functionality for non authorized calls", async () => {
            await expect(minter.connect(random).mintVCWL([], 1000)).to.be.reverted;
            await expect(minter.connect(random).mintCWL([], 1000)).to.be.reverted;
            await expect(minter.connect(random).mintToCWL(random.address, [], 1000))
                .to.be.reverted;
            await expect(minter.connect(random).mintToFinal(random.address, 1000)).to
                .be.reverted;
            await expect(minter.connect(random).mint(1000)).to.be.reverted;
            await expect(minter.connect(random).setVestingFactory(random.address)).to
                .be.reverted;
            await expect(minter.connect(random).mintPremine([random.address], [1000]))
                .to.be.reverted;
            await expect(
                minter.connect(random).mintPremineUS([random.address], [1000])
            ).to.be.reverted;
            await expect(
                minter.connect(random).pullTokensPremine([random.address], [], [1000])
            ).to.be.reverted;
        });
    });
});

const usdcABI = [
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "owner",
                type: "address",
            },
            {
                indexed: true,
                internalType: "address",
                name: "spender",
                type: "address",
            },
            {
                indexed: false,
                internalType: "uint256",
                name: "value",
                type: "uint256",
            },
        ],
        name: "Approval",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "authorizer",
                type: "address",
            },
            {
                indexed: true,
                internalType: "bytes32",
                name: "nonce",
                type: "bytes32",
            },
        ],
        name: "AuthorizationCanceled",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "authorizer",
                type: "address",
            },
            {
                indexed: true,
                internalType: "bytes32",
                name: "nonce",
                type: "bytes32",
            },
        ],
        name: "AuthorizationUsed",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "_account",
                type: "address",
            },
        ],
        name: "Blacklisted",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "newBlacklister",
                type: "address",
            },
        ],
        name: "BlacklisterChanged",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "burner",
                type: "address",
            },
            {
                indexed: false,
                internalType: "uint256",
                name: "amount",
                type: "uint256",
            },
        ],
        name: "Burn",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "newMasterMinter",
                type: "address",
            },
        ],
        name: "MasterMinterChanged",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "minter",
                type: "address",
            },
            {
                indexed: true,
                internalType: "address",
                name: "to",
                type: "address",
            },
            {
                indexed: false,
                internalType: "uint256",
                name: "amount",
                type: "uint256",
            },
        ],
        name: "Mint",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "minter",
                type: "address",
            },
            {
                indexed: false,
                internalType: "uint256",
                name: "minterAllowedAmount",
                type: "uint256",
            },
        ],
        name: "MinterConfigured",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "oldMinter",
                type: "address",
            },
        ],
        name: "MinterRemoved",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "address",
                name: "previousOwner",
                type: "address",
            },
            {
                indexed: false,
                internalType: "address",
                name: "newOwner",
                type: "address",
            },
        ],
        name: "OwnershipTransferred",
        type: "event",
    },
    { anonymous: false, inputs: [], name: "Pause", type: "event" },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "newAddress",
                type: "address",
            },
        ],
        name: "PauserChanged",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "newRescuer",
                type: "address",
            },
        ],
        name: "RescuerChanged",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "from",
                type: "address",
            },
            {
                indexed: true,
                internalType: "address",
                name: "to",
                type: "address",
            },
            {
                indexed: false,
                internalType: "uint256",
                name: "value",
                type: "uint256",
            },
        ],
        name: "Transfer",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "address",
                name: "_account",
                type: "address",
            },
        ],
        name: "UnBlacklisted",
        type: "event",
    },
    { anonymous: false, inputs: [], name: "Unpause", type: "event" },
    {
        inputs: [],
        name: "CANCEL_AUTHORIZATION_TYPEHASH",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "DOMAIN_SEPARATOR",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "PERMIT_TYPEHASH",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "RECEIVE_WITH_AUTHORIZATION_TYPEHASH",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "TRANSFER_WITH_AUTHORIZATION_TYPEHASH",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "owner", type: "address" },
            { internalType: "address", name: "spender", type: "address" },
        ],
        name: "allowance",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "spender", type: "address" },
            { internalType: "uint256", name: "value", type: "uint256" },
        ],
        name: "approve",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "authorizer", type: "address" },
            { internalType: "bytes32", name: "nonce", type: "bytes32" },
        ],
        name: "authorizationState",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "account", type: "address" }],
        name: "balanceOf",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "_account", type: "address" }],
        name: "blacklist",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "blacklister",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "uint256", name: "_amount", type: "uint256" }],
        name: "burn",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "authorizer", type: "address" },
            { internalType: "bytes32", name: "nonce", type: "bytes32" },
            { internalType: "uint8", name: "v", type: "uint8" },
            { internalType: "bytes32", name: "r", type: "bytes32" },
            { internalType: "bytes32", name: "s", type: "bytes32" },
        ],
        name: "cancelAuthorization",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "minter", type: "address" },
            {
                internalType: "uint256",
                name: "minterAllowedAmount",
                type: "uint256",
            },
        ],
        name: "configureMinter",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "currency",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "decimals",
        outputs: [{ internalType: "uint8", name: "", type: "uint8" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "spender", type: "address" },
            { internalType: "uint256", name: "decrement", type: "uint256" },
        ],
        name: "decreaseAllowance",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "spender", type: "address" },
            { internalType: "uint256", name: "increment", type: "uint256" },
        ],
        name: "increaseAllowance",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "string", name: "tokenName", type: "string" },
            { internalType: "string", name: "tokenSymbol", type: "string" },
            { internalType: "string", name: "tokenCurrency", type: "string" },
            { internalType: "uint8", name: "tokenDecimals", type: "uint8" },
            {
                internalType: "address",
                name: "newMasterMinter",
                type: "address",
            },
            { internalType: "address", name: "newPauser", type: "address" },
            {
                internalType: "address",
                name: "newBlacklister",
                type: "address",
            },
            { internalType: "address", name: "newOwner", type: "address" },
        ],
        name: "initialize",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "string", name: "newName", type: "string" }],
        name: "initializeV2",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "lostAndFound", type: "address" },
        ],
        name: "initializeV2_1",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "_account", type: "address" }],
        name: "isBlacklisted",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "account", type: "address" }],
        name: "isMinter",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "masterMinter",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "_to", type: "address" },
            { internalType: "uint256", name: "_amount", type: "uint256" },
        ],
        name: "mint",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "minter", type: "address" }],
        name: "minterAllowance",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "name",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "owner", type: "address" }],
        name: "nonces",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "owner",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "pause",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "paused",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "pauser",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "owner", type: "address" },
            { internalType: "address", name: "spender", type: "address" },
            { internalType: "uint256", name: "value", type: "uint256" },
            { internalType: "uint256", name: "deadline", type: "uint256" },
            { internalType: "uint8", name: "v", type: "uint8" },
            { internalType: "bytes32", name: "r", type: "bytes32" },
            { internalType: "bytes32", name: "s", type: "bytes32" },
        ],
        name: "permit",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "from", type: "address" },
            { internalType: "address", name: "to", type: "address" },
            { internalType: "uint256", name: "value", type: "uint256" },
            { internalType: "uint256", name: "validAfter", type: "uint256" },
            { internalType: "uint256", name: "validBefore", type: "uint256" },
            { internalType: "bytes32", name: "nonce", type: "bytes32" },
            { internalType: "uint8", name: "v", type: "uint8" },
            { internalType: "bytes32", name: "r", type: "bytes32" },
            { internalType: "bytes32", name: "s", type: "bytes32" },
        ],
        name: "receiveWithAuthorization",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "minter", type: "address" }],
        name: "removeMinter",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract IERC20",
                name: "tokenContract",
                type: "address",
            },
            { internalType: "address", name: "to", type: "address" },
            { internalType: "uint256", name: "amount", type: "uint256" },
        ],
        name: "rescueERC20",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "rescuer",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "symbol",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "totalSupply",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "to", type: "address" },
            { internalType: "uint256", name: "value", type: "uint256" },
        ],
        name: "transfer",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "from", type: "address" },
            { internalType: "address", name: "to", type: "address" },
            { internalType: "uint256", name: "value", type: "uint256" },
        ],
        name: "transferFrom",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "newOwner", type: "address" }],
        name: "transferOwnership",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "from", type: "address" },
            { internalType: "address", name: "to", type: "address" },
            { internalType: "uint256", name: "value", type: "uint256" },
            { internalType: "uint256", name: "validAfter", type: "uint256" },
            { internalType: "uint256", name: "validBefore", type: "uint256" },
            { internalType: "bytes32", name: "nonce", type: "bytes32" },
            { internalType: "uint8", name: "v", type: "uint8" },
            { internalType: "bytes32", name: "r", type: "bytes32" },
            { internalType: "bytes32", name: "s", type: "bytes32" },
        ],
        name: "transferWithAuthorization",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "_account", type: "address" }],
        name: "unBlacklist",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "unpause",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "_newBlacklister",
                type: "address",
            },
        ],
        name: "updateBlacklister",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "_newMasterMinter",
                type: "address",
            },
        ],
        name: "updateMasterMinter",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "_newPauser", type: "address" }],
        name: "updatePauser",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "address", name: "newRescuer", type: "address" }],
        name: "updateRescuer",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "version",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        stateMutability: "view",
        type: "function",
    },
];

const daiABI = [
    {
        inputs: [{ internalType: "uint256", name: "chainId_", type: "uint256" }],
        payable: false,
        stateMutability: "nonpayable",
        type: "constructor",
    },
    {
        anonymous: false,
        inputs: [
            { indexed: true, internalType: "address", name: "src", type: "address" },
            { indexed: true, internalType: "address", name: "guy", type: "address" },
            { indexed: false, internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "Approval",
        type: "event",
    },
    {
        anonymous: true,
        inputs: [
            { indexed: true, internalType: "bytes4", name: "sig", type: "bytes4" },
            { indexed: true, internalType: "address", name: "usr", type: "address" },
            { indexed: true, internalType: "bytes32", name: "arg1", type: "bytes32" },
            { indexed: true, internalType: "bytes32", name: "arg2", type: "bytes32" },
            { indexed: false, internalType: "bytes", name: "data", type: "bytes" },
        ],
        name: "LogNote",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            { indexed: true, internalType: "address", name: "src", type: "address" },
            { indexed: true, internalType: "address", name: "dst", type: "address" },
            { indexed: false, internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "Transfer",
        type: "event",
    },
    {
        constant: true,
        inputs: [],
        name: "DOMAIN_SEPARATOR",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: true,
        inputs: [],
        name: "PERMIT_TYPEHASH",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: true,
        inputs: [
            { internalType: "address", name: "", type: "address" },
            { internalType: "address", name: "", type: "address" },
        ],
        name: "allowance",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "usr", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "approve",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: true,
        inputs: [{ internalType: "address", name: "", type: "address" }],
        name: "balanceOf",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "usr", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "burn",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: true,
        inputs: [],
        name: "decimals",
        outputs: [{ internalType: "uint8", name: "", type: "uint8" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: false,
        inputs: [{ internalType: "address", name: "guy", type: "address" }],
        name: "deny",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "usr", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "mint",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "src", type: "address" },
            { internalType: "address", name: "dst", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "move",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: true,
        inputs: [],
        name: "name",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: true,
        inputs: [{ internalType: "address", name: "", type: "address" }],
        name: "nonces",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "holder", type: "address" },
            { internalType: "address", name: "spender", type: "address" },
            { internalType: "uint256", name: "nonce", type: "uint256" },
            { internalType: "uint256", name: "expiry", type: "uint256" },
            { internalType: "bool", name: "allowed", type: "bool" },
            { internalType: "uint8", name: "v", type: "uint8" },
            { internalType: "bytes32", name: "r", type: "bytes32" },
            { internalType: "bytes32", name: "s", type: "bytes32" },
        ],
        name: "permit",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "usr", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "pull",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "usr", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "push",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: false,
        inputs: [{ internalType: "address", name: "guy", type: "address" }],
        name: "rely",
        outputs: [],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: true,
        inputs: [],
        name: "symbol",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: true,
        inputs: [],
        name: "totalSupply",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "dst", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "transfer",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: false,
        inputs: [
            { internalType: "address", name: "src", type: "address" },
            { internalType: "address", name: "dst", type: "address" },
            { internalType: "uint256", name: "wad", type: "uint256" },
        ],
        name: "transferFrom",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        constant: true,
        inputs: [],
        name: "version",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
    {
        constant: true,
        inputs: [{ internalType: "address", name: "", type: "address" }],
        name: "wards",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        payable: false,
        stateMutability: "view",
        type: "function",
    },
];
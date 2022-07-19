
const { default: axios } = require("axios");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { ethers, network } = require("hardhat");
const { signEIP712Message } = require("./eip712sign");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");

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

const fsdDeployerHelper = (async () => {
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

    return {
        fsd,
        fsdNetwork
    }
});
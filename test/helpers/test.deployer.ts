const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { ethers } = require("hardhat");
const { expect } = require("chai");
const { createPoolNewAddress, SIGNER_ACCOUNT } = require("./base");
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const fsdContractsDeployer = async (owner: SignerWithAddress) => {
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
    owner.address, //governance Address
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
    owner,
    fsd,
    fsdNetwork,
    fundingPool,
    premiumsPool,
    timelock,
    formula,
    conviction,
    dao,
    vestingFactory,
    vestingPRE,
    vestingKOL,
    vestingVC,
    minter,
  };
};

export default fsdContractsDeployer;

// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat")
const { web3 } = require("@openzeppelin/test-helpers/src/setup")
const { ethers } = require("hardhat")
const { signEIP712Message } = require("../test/helpers/eip712sign");


const SIGNER_ACCOUNT = {
  publicKey: "0xC6C23De51657dd9C2C4F921Ffa66CCFe3C2FbFD9",
  privateKey: Buffer.from(
    "4626faca3179addddacb3cb60ba3fe5b0943d11de9afbded0154b379df7ba5f4",
    "hex"
  ),
}

const createPoolNewAddress = () => {
  const addr = web3.eth.accounts.create()
  return web3.utils.toChecksumAddress(addr.address)
}

async function main() {
  const [owner] = await hre.ethers.getSigners()
  console.log("Deploying contract with owner address : ", owner.address)
  console.log("Signer account : ", SIGNER_ACCOUNT.publicKey)

  let MockToken = await ethers.getContractFactory("MockToken")
  let xDai = await MockToken.deploy("xDAITEST", "xDAITEST", 18)
  await xDai.deployed()
  await xDai.mint(owner.address, ethers.utils.parseEther("100000000000"))
  console.log("Added xDAI test and in address : ", xDai.address)





  // Deploy pools
  const fundingPool = createPoolNewAddress()
  console.log("Created funding pool address : ", fundingPool)
  const premiumsPool = createPoolNewAddress()
  console.log("Created premiums pool with address : ", premiumsPool)

  // Deploy timelock
  let timelock = await ethers.getContractFactory("Timelock")
  timelock = await timelock.deploy(owner.address, 360000)
  console.log("Created timelock with address : ", timelock.address)

  // Deploy formula
  let formula = await ethers.getContractFactory("FairSideFormula")
  formula = await formula.deploy()
  console.log("Created formula with address : ", formula.address)

  // Deploy FSD
  let fsd = await ethers.getContractFactory("FSD", {
    libraries: {
      FairSideFormula: formula.address,
    },
  })
  fsd = await fsd.deploy(fundingPool, timelock.address)
  await fsd.deployed()
  console.log("Created fsd with address : ", fsd.address)

  // Deploy conviction
  let conviction = await ethers.getContractFactory("FairSideConviction")
  conviction = await conviction.deploy(fsd.address)
  console.log("Created conviction with address : ", conviction.address)

  // Deploy dao
  let dao = await ethers.getContractFactory("FairSideDAO")
  dao = await dao.deploy(timelock.address, fsd.address, owner.address)
  console.log("Created dao with address : ", dao.address)

  // Deploy minter
  let minter = await ethers.getContractFactory("FSDMinter")
  minter = await minter.deploy(fsd.address, SIGNER_ACCOUNT.publicKey)
  console.log("Created minter with address : ", minter.address)

  // Deploy vesting factory
  let vestingFactory = await ethers.getContractFactory("FSDVestingFactory")
  vestingFactory = await vestingFactory.deploy(minter.address)
  console.log("Created vesting factory with address : ", vestingFactory.address)

  // Set the vesting factory on minter
  await minter.setVestingFactory(vestingFactory.address);
  console.log("Setting the vesting contract factory")

  // Deploy Network
  let fsdNetwork = await ethers.getContractFactory("FSDNetwork", {
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
  console.log("Created network with address : ", fsdNetwork.address)

  // Set conviction to fsd
  await fsd.connect(owner).setFairSideConviction(conviction.address)

  console.log("Setting the conviction contract to fsd")

  // Set network to fsd
  await fsd.connect(owner).setFairSideNetwork(fsdNetwork.address)

  console.log("Setting the fsd network contract to fsd")

  // Set minter to fsd
  await fsd.connect(owner).setMinter(minter.address)

  console.log("Setting the minter contract to fsd")

  // Set Crs to network
  await fsdNetwork.connect(owner).setCsrTypes(155, true)

  console.log("Setting the crs type to fsd network")

  // Deploy Vesting pre
  let vestingPRE = await ethers.getContractFactory("FSDVestingPRE");
  vestingPRE = await vestingPRE.deploy(
    fsd.address,
    vestingFactory.address,
    minter.address,
    dao.address,
    conviction.address
  );

  console.log("Created vesting pre template with address : ", vestingPRE.address)

  // Deploy Vesting KOL
  let vestingKOL = await ethers.getContractFactory("FSDVestingKOL");
  vestingKOL = await vestingKOL.deploy(
    fsd.address,
    vestingFactory.address,
    minter.address,
    dao.address,
    conviction.address
  );

  console.log("Created vesting kol template with address : ", vestingKOL.address)


  // Deploy Vesting VC
  let vestingVC = await ethers.getContractFactory("FSDVestingVC");
  vestingVC = await vestingVC.deploy(
    fsd.address,
    vestingFactory.address,
    minter.address,
    dao.address,
    conviction.address
  );

  console.log("Created vesting vc template with address : ", vestingVC.address)

  // set the starting implementation
  await vestingFactory.setImplementation(vestingPRE.address);
  console.log("Setting the implementation template to vesting pre")

  await minter.mintPremine([owner.address], [1000000]);
  await minter.mintPremineUS([owner.address], [1000000]);
  await fsd.phaseAdvance();
  await vestingFactory.setImplementation(vestingKOL.address);
  await minter.mintPremine([owner.address], [1000000]);
  await fsd.phaseAdvance();
  await vestingFactory.setImplementation(vestingVC.address);
  // const sigVc1 = signEIP712Message(
  //   minter.address,
  //   owner.address,
  //   SIGNER_ACCOUNT.privateKey
  // );
  // await minter
  //       .mintVCWL(sigVc1, 1000000, { value: ethers.utils.parseEther("500") });

  //       await fsd.phaseAdvance();
  //       await minter

  //       .mintCWL(sigVc1, 1000000, { value: ethers.utils.parseEther("10") });
  //       await fsd.phaseAdvance();
  //       await minter.mint(1, {
  //         value: ethers.utils.parseEther("100"),
  //       });
  console.log("DONE")
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
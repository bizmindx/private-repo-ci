// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const { expect } = require("chai");


const SIGNER_ACCOUNT = {
  publicKey: "0xC6C23De51657dd9C2C4F921Ffa66CCFe3C2FbFD9",
  privateKey: Buffer.from(
    "4626faca3179addddacb3cb60ba3fe5b0943d11de9afbded0154b379df7ba5f4",
    "hex"
  ),
};

const createPoolNewAddress = () => {
  const addr = web3.eth.accounts.create();
  console.log("Address : ", addr.address);
  console.log("PrivateKey : ", addr.privateKey);
  return web3.utils.toChecksumAddress(addr.address);
};

async function main() {

  let [owner, acc2, acc3, accUSA] = await ethers.getSigners();
  
  console.log("Deploying contract with owner address : ", owner.address);
  console.log("Signer account : ", SIGNER_ACCOUNT.publicKey);


  // Deploy pools
  const fundingPool = createPoolNewAddress();
  console.log("Created funding pool address : ", fundingPool);
  const premiumsPool = createPoolNewAddress();
  console.log("Created premiums pool with address : ", premiumsPool);

  // Deploy timelock
  let timelock = await ethers.getContractFactory("Timelock");
  timelock = await timelock.connect(owner).deploy(owner.address, 360000);
  await timelock.deployed()
  console.log("Created timelock with address : ", timelock.address);

  // Deploy formula
  let formula = await ethers.getContractFactory("FairSideFormula");
  formula = await formula.connect(owner).deploy();
  await formula.deployed()
  console.log("Created formula with address : ", formula.address);

  // Deploy FSD
  let fsd = await ethers.getContractFactory("FSD", {
    libraries: {
      FairSideFormula: formula.address,
    },
  });
  fsd = await fsd.connect(owner).deploy(fundingPool, timelock.address);
  await fsd.deployed()
  console.log("Created fsd with address : ", fsd.address);

  // Deploy conviction
  let conviction = await ethers.getContractFactory("FairSideConviction");
  conviction = await conviction.connect(owner).deploy(fsd.address);
  await conviction.deployed()
  console.log("Created conviction with address : ", conviction.address);

  // Deploy dao
  let dao = await ethers.getContractFactory("FairSideDAO");
  dao = await dao
    .connect(owner)
    .deploy(timelock.address, fsd.address, owner.address);
    await dao.deployed()
  console.log("Created dao with address : ", dao.address);

  // Deploy minter
  let minter = await ethers.getContractFactory("FSDMinter");
  minter = await minter
    .connect(owner)
    .deploy(fsd.address, SIGNER_ACCOUNT.publicKey);
    await minter.deployed()
  console.log("Created minter with address : ", minter.address);

  // Deploy vesting factory
  let vestingFactory = await ethers.getContractFactory("FSDVestingFactory");
  vestingFactory = await vestingFactory.connect(owner).deploy(minter.address);
  await vestingFactory.deployed()
  console.log(
    "Created vesting factory with address : ",
    vestingFactory.address
  );

  // Set the vesting factory on minter
  await minter.connect(owner).setVestingFactory(vestingFactory.address);
  console.log("Setting the vesting contract factory");

  // Deploy Network
  let fsdNetwork = await ethers.getContractFactory("FSDNetwork", {
    libraries: {
      FairSideFormula: formula.address,
    },
  });
  fsdNetwork = await fsdNetwork
    .connect(owner)
    .deploy(
      fsd.address,
      fundingPool,
      premiumsPool,
      owner.address,
      timelock.address
    );

    await fsdNetwork.deployed()

  console.log("Created network with address : ", fsdNetwork.address);

  // Set conviction to fsd
  await fsd.setFairSideConviction(conviction.address);

  console.log("Setting the conviction contract to fsd");

  // Set network to fsd
  await fsd.setFairSideNetwork(fsdNetwork.address);

  console.log("Setting the fsd network contract to fsd");

  // Set minter to fsd
  await fsd.setMinter(minter.address);

  console.log("Setting the minter contract to fsd");

  // Set Crs to network
  await fsdNetwork.connect(owner).setCsrTypes(155, true);

  console.log("Setting the crs type to fsd network");

  // Deploy Vesting pre
  let vestingPRE = await ethers.getContractFactory("FSDVestingPRE");
  vestingPRE = await vestingPRE
    .connect(owner)
    .deploy(
      fsd.address,
      vestingFactory.address,
      minter.address,
      dao.address,
      conviction.address
    );
await vestingPRE.deployed()
  console.log(
    "Created vesting pre template with address : ",
    vestingPRE.address
  );

  // Deploy Vesting KOL
  let vestingKOL = await ethers.getContractFactory("FSDVestingKOL");
  vestingKOL = await vestingKOL
    .connect(owner)
    .deploy(
      fsd.address,
      vestingFactory.address,
      minter.address,
      dao.address,
      conviction.address
    );
    await vestingKOL.deployed()

  console.log(
    "Created vesting kol template with address : ",
    vestingKOL.address
  );

  // Deploy Vesting VC
  let vestingVC = await ethers.getContractFactory("FSDVestingVC");
  vestingVC = await vestingVC
    .connect(owner)
    .deploy(
      fsd.address,
      vestingFactory.address,
      minter.address,
      dao.address,
      conviction.address
    );
    await vestingVC.deployed()

  console.log("Created vesting vc template with address : ", vestingVC.address);

  // set the starting implementation
  await sendTx(
    vestingFactory.connect(owner).setImplementation(vestingPRE.address)
  );
  console.log("Setting the implementation template to vesting pre");

  // mint premine
  await sendTx(
    minter
      .connect(owner)
      .mintPremine([owner.address], [ethers.utils.parseEther("1100000")])
  );
  
  console.log("Minted the premine");
  const ownerVesting = await minter.userVesting(owner.address);
  console.log("Owner Vesting : ", ownerVesting);
  console.log("Owner balance : ", await fsd.balanceOf(ownerVesting));

  // mint USA
  await sendTx(
    minter
      .connect(owner)
      .mintPremineUS(
        [owner.address, accUSA.address],
        [ethers.utils.parseEther("1100000"), ethers.utils.parseEther("1100000")]
      )
  );

  console.log("Minted the premine USA");

  console.log("AccUSA balance : ", await fsd.balanceOf(accUSA.address));
  // TODO: need to pull those tokens back in

  // set the KOL implementation
  await sendTx(
    vestingFactory.connect(owner).setImplementation(vestingKOL.address)
  );
  console.log("Setting the implementation template to vesting KOL");

  // mint KOL
  await sendTx(
    minter
      .connect(owner)
      .mintPremine([acc2.address], [ethers.utils.parseEther("1100000")])
  );

  console.log("Minted the KOL");

  const acc2Vesting = await minter.userVesting(acc2.address);

  console.log("Acc2 Vesting : ", acc2Vesting);

  console.log("Acc2 balance : ", await fsd.balanceOf(acc2Vesting));

  // set the VC implementation
  await sendTx(
    vestingFactory.connect(owner).setImplementation(vestingVC.address)
  );
  console.log("Setting the implementation template to vesting VC");

  // mint VC
  await sendTx(
    minter
      .connect(owner)
      .mintPremine([acc3.address], [ethers.utils.parseEther("1100000")])
  );

  console.log("Minted the VC");

  const acc3Vesting = await minter.userVesting(acc3.address);

  console.log("Acc3 Vesting : ", acc3Vesting);

  console.log("Acc3 balance : ", await fsd.balanceOf(acc3Vesting));

  await fsd.phaseAdvance();

  await owner.sendTransaction({
    to: fsd.address,
    value: ethers.utils.parseEther("5000"),
  });
  console.log("Phase advanced and moved 5000 ETH to capital pool(FSD)");

  console.log("Now we are going to start creating events");

  console.log("Owner : ", await fsd.balanceOf(owner.address));

  await sendTx(fsd.phaseAdvance());
  await sendTx(fsd.phaseAdvance());

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function sendTx(...txs) {
  if (txs.length == 1) {
    return (await txs[0]).wait();
  }
  return Promise.all(txs.map(async (tx) => (await tx).wait()));
}
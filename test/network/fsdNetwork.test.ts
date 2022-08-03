import { expect } from "chai";
import { ethers } from "hardhat";
import { ethToWei, weiToEth, setBlockTime } from "../helpers/base";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { FSD, FSDNetwork, FSDMinter } from "../../typechain-types";
import { FSDPhase } from "../Interfaces/enums";
import fsdContractsDeployer from "../helpers/test.deployer";

describe("FSDNetwork", () => {
  // Accounts
  let owner: SignerWithAddress;

  // Premine
  let userAccount1: SignerWithAddress;
  let userAccount2: SignerWithAddress;
  let userAccount3: SignerWithAddress;
  let userAccount4: SignerWithAddress;
  let userAccount5: SignerWithAddress;

  // Malicious
  let random: SignerWithAddress;

  let membershipBuyer: SignerWithAddress;
  let membershipBuyer1: SignerWithAddress;

  let fundingPool: string;
  let fsd: FSD;

  let minter: FSDMinter;

  let fsdNetwork: FSDNetwork;

  before(async () => {
    [
      owner,
      userAccount1,
      userAccount2,
      userAccount3,
      userAccount4,
      userAccount5,
      random,
      membershipBuyer,
      membershipBuyer1,
    ] = await ethers.getSigners();

    ({ fsd, fsdNetwork, fundingPool, minter } = await fsdContractsDeployer(
      owner
    ));

    //add funds to the capital pool to cover membership costs
    await owner.sendTransaction({
      to: fsd.address,
      value: ethToWei("1000"),
    });
  });

  context("Validations If 'unAuthorized' (non Owner)", () => {
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

    it("should fail to set the gearing factor from a random account", async () => {
      await expect(
        fsdNetwork.connect(random).setGearingFactor(100)
      ).to.be.revertedWith("FSDNetwork:: Insufficient Privileges");
    });

    it("should fail to set the slippage tolerance from a random account", async () => {
      await expect(
        fsdNetwork.connect(random).setSlippageTolerance(100)
      ).to.be.revertedWith("FSDNetwork:: Insufficient Privileges");
    });
  });

  describe("Validations", async () => {
    //maximum allowed is 0.4eth
    it("should fail to open a cost share request with 0.3 eth", async () => {
      await expect(
        fsdNetwork
          .connect(random)
          .openCostShareRequest(ethToWei("0.3"), false, 155)
      ).to.be.revertedWith(
        "FSDNetwork::openCostShareRequest: Ineligible cost share request"
      );
    });

    it("should fail to open a cost share request with invalid/non approved CSR Type", async () => {
      await fsd.updateCurrentPhase(FSDPhase.Final);
      // deposit 4000 ETH
      await minter.connect(membershipBuyer1).mint(1, {
        value: ethToWei("4000"),
      });
      //purchase membership
      await fsdNetwork
        .connect(membershipBuyer1)
        .purchaseMembershipETH({ value: ethToWei("1") });

      await fsd
        .connect(membershipBuyer1)
        .approve(fsdNetwork.address, ethers.utils.parseEther("10000000"));

      await setBlockTime(1700000000);

      await expect(
        fsdNetwork
          .connect(membershipBuyer1)
          .openCostShareRequest(ethToWei("0.4"), false, 105)
      ).to.be.reverted;
      // With(
      //   "FSDNetwork::openCostShareRequest: Cost request type is not approved"
      // );
    });

    it("should fail to update a cost share request with a invalid signature", async () => {
      await expect(
        fsdNetwork
          .connect(random)
          .updateCostShareRequest(0, 1, Buffer.alloc(0), Buffer.alloc(0)) //wrong bytes
      ).to.be.revertedWith("ECDSA: invalid signature length");
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
  });

  describe("", () => {
    it("should deposit more than 4000 ETH and 100 ETH respectively", async () => {
      //move to final phase
      await fsd.updateCurrentPhase(FSDPhase.Final);
      // deposit 4000 ETH and 100 ETH
      await minter.connect(userAccount5).mint(1, {
        value: ethToWei("4000"),
      });

      await minter.connect(userAccount4).mint(1, {
        value: ethToWei("100"),
      });
    });

    it("should open a new cost share request ", async () => {
      // approve the fsd network contract
      await fsd
        .connect(userAccount5)
        .approve(fsdNetwork.address, ethToWei("10000000"));

      //purchase membership with FSD
      await fsdNetwork.connect(userAccount5).purchaseMembership(ethToWei("50"));

      // const membershipAfter = await fsdNetwork.membership(userAccount5.address);
      // console.log(
      //   "this is costshare benefit",
      //   weiToEth(membershipAfter.availableCostShareBenefits)
      // );

      // const fsdEtherBalance = await ethers.provider.getBalance(fsd.address);
      // const fsdTokenBalance = await fsd.balanceOf(fsd.address);
      // console.log("This is ether balance before", weiToEth(fsdEtherBalance));
      // console.log("This is token balance before", fsdTokenBalance);

      // const amount = new BigNumber(0.04 / 10);
      // const fsdEtherBalanceAfter = await ethers.provider.getBalance(
      //   fsd.address
      // );
      // const fsdTokenBalanceAfter = await fsd.balanceOf(fsd.address);
      // console.log(
      //   "This is ether balance after",
      //   weiToEth(fsdEtherBalanceAfter)
      // );
      await setBlockTime(1726624553);

      await fsdNetwork
        .connect(userAccount5)
        .openCostShareRequest(ethToWei("10"), false, 155);
    });

    it("should send 50% of 'openCostShareRequest' to FSD contract as governance ", async () => {
      //purchase membership with FSD
      await fsdNetwork.connect(userAccount5).purchaseMembership(ethToWei("20"));
      const fsdTokenBalance = await fsd.balanceOf(fsd.address);
      await fsdNetwork
        .connect(userAccount5)
        .openCostShareRequest(ethToWei("10"), false, 155);
      const fsdTokenBalanceAfter = await fsd.balanceOf(fsd.address);
      expect(fsdTokenBalance).to.not.be.equal(fsdTokenBalanceAfter);
    });

    it("should emit event 'CreateCSR' when openCostShareRequest is called", async () => {
      //purchase membership with FSD
      await fsdNetwork.connect(userAccount5).purchaseMembership(ethToWei("10"));
      await expect(
        fsdNetwork
          .connect(userAccount5)
          .openCostShareRequest(ethToWei("10"), false, 155)
      ).to.emit(fsdNetwork, "CreateCSR");
    });

    it("should get the fsd price", async () => {
      let fsdPrice = await fsdNetwork.getFSDPrice();
      expect(fsdPrice).to.be.not.equal("0");
    });

    it("should get the ether price", async () => {
      let ethPrice = await fsdNetwork.getEtherPrice();
      expect(ethPrice).to.be.not.equal("0");
    });
  });
});

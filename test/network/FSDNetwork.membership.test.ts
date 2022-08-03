import { expect } from "chai";
import { ethers } from "hardhat";
import { ZERO_ADDRESS } from "@openzeppelin/test-helpers/src/constants";
import { ethToWei, advanceBlocks } from "../helpers/base";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { FSD, FSDNetwork, FSDMinter } from "../../typechain-types";
import { FSDPhase } from "../Interfaces/enums";
import fsdContractsDeployer from "../helpers/test.deployer";

describe("FSDNetwork::Membership", () => {
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

    await fsd.updateCurrentPhase(FSDPhase.Final);

    //add funds to the capital pool to cover membership costs
    await owner.sendTransaction({
      to: fsd.address,
      value: ethToWei("1000"),
    });
  });

  it("should fail to set the membership fee from a random account", async () => {
    await expect(
      fsdNetwork.connect(random).setMembershipFee(100)
    ).to.be.revertedWith("FSDNetwork:: Insufficient Privileges");
  });

  //minimum is 0.4 eth
  it("should fail to purchase membership with 0.3 eth", async () => {
    await expect(
      fsdNetwork
        .connect(random)
        .purchaseMembershipETH({ value: ethToWei("0.3") })
    ).to.be.revertedWith(
      "FSDNetwork::purchaseMembershipETH: Invalid cost share benefit specified"
    );
  });

  it("should fail to set membership wallets after membership expiry", async () => {
    await expect(
      fsdNetwork
        .connect(random)
        .setMembershipWallets([membershipBuyer1.address, random.address])
    ).to.be.revertedWith(
      "FSDNetwork::setMembershipWallets: Membership expired"
    );
  });
  //maximum allowed is 100 ETH
  it("should fail to to purchase membership with 1000 eth", async () => {
    await expect(
      fsdNetwork
        .connect(random)
        .purchaseMembershipETH({ value: ethToWei("1000") })
    ).to.be.revertedWith(
      "FSDNetwork::purchaseMembershipETH: Exceeds cost share benefit limit per account"
    );
  });

  it("should fail to purchase membership with 1 eth when there is no capital to cover it", async () => {
    await expect(
      fsdNetwork.connect(random).purchaseMembershipETH({ value: ethToWei("1") })
    ).to.be.revertedWith(
      "FSDNetwork::purchaseMembershipETH: Insufficient Capital to Cover Membership"
    );
  });

  it("should add capital to pool to cover membership", async () => {
    await minter.connect(userAccount5).mint(1, {
      value: ethToWei("4000"),
    });

    await minter.connect(userAccount4).mint(1, {
      value: ethToWei("100"),
    });

    await minter.connect(userAccount1).mint(1, {
      value: ethToWei("100"),
    });
  });

  it("should purchase membership with ETH", async () => {
    //move to final phase
    await fsd.updateCurrentPhase(FSDPhase.Final);

    const fundingpoolBalance = await ethers.provider.getBalance(fsd.address);
    await minter.connect(membershipBuyer).mint(1, {
      value: ethToWei("100"),
    });

    await fsdNetwork
      .connect(membershipBuyer)
      .purchaseMembershipETH({ value: ethToWei("1") });

    const fundingpoolBalanceAfter = await ethers.provider.getBalance(
      fundingPool
    );
    expect(fundingpoolBalance).to.not.be.equal(fundingpoolBalanceAfter);
  });

  // it("should expire membership after 435 days ", async () => {
  //   //move to final phase
  //   await fsd.updateCurrentPhase(FSDPhase.Final);

  //   const fundingpoolBalance = await ethers.provider.getBalance(fsd.address);
  //   await minter.connect(membershipBuyer).mint(1, {
  //     value: ethToWei("100"),
  //   });

  //   await fsdNetwork
  //     .connect(membershipBuyer)
  //     .purchaseMembershipETH({ value: ethToWei("1") });

  //   const fundingpoolBalanceAfter = await ethers.provider.getBalance(
  //     fundingPool
  //   );
  //   expect(fundingpoolBalance).to.not.be.equal(fundingpoolBalanceAfter);
  // });

  it("should purchase membership with FSD", async () => {
    await advanceBlocks(5);
    // approve the fsd network contract
    await fsd
      .connect(userAccount5)
      .approve(fsdNetwork.address, ethToWei("10000000"));

    // purchase membership with FSD
    await fsdNetwork.connect(userAccount5).purchaseMembership(ethToWei("100"));

    // make sure that we the user is getting his position and that the state is updated properly
    expect(await fsdNetwork.membership(userAccount5.address)).to.not.equal([]);
    expect(await fsdNetwork.totalCostShareBenefits()).to.equal(
      "101000000000000000000"
    );
  });

  it("should update membership state after membership is purchased with ETH", async () => {
    const beforeMembershipPurchase = await fsdNetwork.membership(
      userAccount1.address
    );

    await fsdNetwork
      .connect(userAccount1)
      .purchaseMembershipETH({ value: ethToWei("1") });

    const afterMembershipPurchase = await fsdNetwork.membership(
      userAccount1.address
    );

    await expect(beforeMembershipPurchase.availableCostShareBenefits).to.equal(
      "0"
    );
    expect(afterMembershipPurchase.availableCostShareBenefits).to.equal(
      ethToWei("1")
    );
  });

  it("should update membership state after membership is purchased with FSD", async () => {
    const beforeMembershipPurchase = await fsdNetwork.membership(
      userAccount4.address
    );
    await advanceBlocks(5);
    // approve the fsd network contract
    await fsd
      .connect(userAccount4)
      .approve(fsdNetwork.address, ethToWei("100000"));

    // purchase membership with FSD
    await fsdNetwork.connect(userAccount4).purchaseMembership(ethToWei("20"));

    const afterMembershipPurchase = await fsdNetwork.membership(
      userAccount4.address
    );

    await expect(beforeMembershipPurchase.availableCostShareBenefits).to.equal(
      "0"
    );
    expect(afterMembershipPurchase.availableCostShareBenefits).to.equal(
      ethToWei("20")
    );
  });

  it("should set membership wallets after membership purchase", async () => {
    await fsdNetwork
      .connect(membershipBuyer)
      .setMembershipWallets([userAccount5.address, userAccount1.address]);
  });

  it("should fail to set membership wallets after wallets have been set", async () => {
    await expect(
      fsdNetwork
        .connect(membershipBuyer)
        .setMembershipWallets([userAccount5.address, userAccount1.address])
    ).to.revertedWith(
      "FSDNetwork::setMembershipWallets: Membership wallet already set"
    );
  });

  it("should fail to set membership wallets when wallets not unique", async () => {
    await expect(
      fsdNetwork
        .connect(userAccount1)
        .setMembershipWallets([userAccount5.address, userAccount5.address])
    ).to.be.revertedWith(
      "FSDNetwork::setMembershipWallets: Addresses Not Unique"
    );
  });

  it("should fail to set membership wallet with invalid address", async () => {
    await expect(
      fsdNetwork
        .connect(userAccount1)
        .setMembershipWallets([ZERO_ADDRESS, userAccount5.address])
    ).to.be.revertedWith("FSDNetwork::setMembershipWallets: Invalid Addresses");
  });
});

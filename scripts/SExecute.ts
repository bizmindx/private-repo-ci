import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";

async function main() {
  let owner: SignerWithAddress = await ethers.getSigners();

  let MockToken = await ethers.getContractFactory("MockToken");
  let aave = await MockToken.connect(owner).deploy("AAVE", "AAVE", 18);
  console.log("Deployed AAVE with address : ", aave.address);
  let curve = await MockToken.connect(owner).deploy("CURVE", "CURVE", 18);
  console.log("Deployed CURVE with address : ", curve.address);

  let fsd = await ethers.getContractAt(
    "contracts/token/FSD.sol:FSD",
    "0x2Dd78Fd9B8F40659Af32eF98555B8b31bC97A351"
  );
  let fsdNetwork = await ethers.getContractAt(
    "contracts/network/FSDNetwork.sol:FSDNetwork",
    "0xAdE429ba898c34722e722415D722A70a297cE3a2"
  );

  for (let i = 0; i < 1000; i++) {
    console.log("INDEX : ", i);
    let privateKey = await ethers.Wallet.createRandom();
    let provider = ethers.getDefaultProvider();
    let newAcc = new ethers.Wallet(privateKey, provider);

    console.log("Created new account with address : ", newAcc.address);

    console.log("Give new created account random positions on AAVE and Curve");

    let random = Math.floor(Math.random() * 1000 + 1);

    random = random.toString();

    await aave.mint(newAcc.address, ethers.utils.parseEther(random));

    console.log("Minted AAVE for newAcc : ", random);

    random = Math.floor(Math.random() * 1000 + 1);

    random = random.toString();

    await curve.mint(newAcc.address, ethers.utils.parseEther(random));

    console.log("Minted CURVE for newAcc : ", random);

    await owner.sendTransaction({
      to: newAcc.address,
      value: ethers.utils.parseEther("100"),
    });

    await owner.sendTransaction({
      to: newAcc.address,
      value: ethers.utils.parseEther("100"),
    });

    await sleep(20000);

    await sendTx(
      owner.sendTransaction({
        to: fsd.address,
        value: ethers.utils.parseEther("5"),
      })
    );
    console.log("Sent 10 eth to the new address");

    let transfer = await sendTx(
      fsd
        .connect(owner)
        .transfer(newAcc.address, ethers.utils.parseEther("1000"), {
          gasLimit: 7500000,
        })
    );

    console.log(
      "Balance of new account FSD : ",
      await fsd.balanceOf(newAcc.address)
    );
    console.log(
      "Balance of new account ETH : ",
      await provider.getBalance(newAcc.address)
    );
    console.log("Transfered 1000 FSD to the new address");

    await sendTx(
      fsd
        .connect(newAcc)
        .approve(fsdNetwork.address, ethers.utils.parseEther("1000000000"), {
          gasLimit: 7500000,
        })
    );
    await sendTx(
      fsdNetwork.connect(newAcc).purchaseMembershipETH({
        value: ethers.utils.parseEther("1"),
        gasLimit: 7500000,
      })
    );

    console.log("Payed a new membership for 1 eth for the new address");

    let wallets = [
      "0x5E1a8A405E0D7b7824d6BF587596D8af4054B58a",
      "0xA7dA285915CBd312F64606c152441046deA12A1b",
    ];
    await fsdNetwork.connect(newAcc).setMembershipWallets(wallets);
    console.log("Set wallets");
    sleep(1000);
  }
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

import { expect } from "chai";
import { ethers } from "hardhat"
import { Contract } from "ethers"

describe("Snapshot", function () {
  let snapshot:Contract;

  beforeEach(async function () {
    const Snapshot = await ethers.getContractFactory("Snapshot")
    const snapshot = await Snapshot.deploy()
    await snapshot.waitForDeployment();
    console.log(`Snapshot deployed to address: ${await snapshot.getAddress()}`)
  })

  it("deposit", async function () {
    await snapshot.deposit(42)
    expect((await snapshot.retrieve()).toString()).to.equal('42');
  })
})

import { expect } from "chai";
import { ethers } from "hardhat"
import { Contract } from "ethers"

describe("Box", function () {
  let box:Contract;

  beforeEach(async function () {
    const Box = await ethers.getContractFactory("Box")
    const box = await Box.deploy()
    await box.waitForDeployment();
    console.log(`Box deployed to address: ${await box.getAddress()}`)
  })

  it("should retrieve value previously stored", async function () {
    await box.store(42)
    expect((await box.retrieve()).toString()).to.equal('42');

    await box.store(100)
    expect((await box.retrieve()).toString()).to.equal('100');
  })
})

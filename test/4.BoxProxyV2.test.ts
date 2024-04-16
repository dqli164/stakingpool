import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { Contract, BigNumber } from "ethers"

describe("Box (proxy) V2", function() {
    let box:Contract
    let boxV2:Contract

    beforeEach(async function() {
        const Box = await ethers.getContractFactory("Box")
        const BoxV2 = await ethers.getContractFactory("BoxV2")

        // initialize with 42
        // 部署Box的第一个版本
        box = await upgrades.deployProxy(Box, [42], {initializer: 'store'})
        // 升级Box到V2版本
        boxV2 = await upgrades.upgradeProxy(await box.getAddress(), BoxV2)

    })
  it("should retrieve value previously stored and increment correctly", async function () {
    expect((await boxV2.retrieve()).toString()).to.equal('42');

    await boxV2.increment()
    expect((await boxV2.retrieve()).toString()).to.equal('43')

    await boxV2.store(100)
    expect((await boxV2.retrieve()).toString()).to.equal('100')
  })

})

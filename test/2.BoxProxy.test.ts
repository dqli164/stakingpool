import { expect } from 'chai'
import { ethers, upgrades } from 'hardhat'
import { Contract } from 'ethers'

describe("Box (proxy)", function() {
    let box:Contract

    beforeEach(async function() {
        const Box = await ethers.getContractFactory('Box')
        // initialize with 42
        box = await upgrades.deployProxy(Box, [42], {initializer: 'store'})
    })

    it("should retrieve value previously stored", async function() {
        expect((await box.retrieve()).toString()).to.equal('42')

        await box.store(100)
        expect((await box.retrieve()).toString()).to.equal('100')
    })
})

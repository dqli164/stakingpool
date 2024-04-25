import { ethers, upgrades } from "hardhat"

async function main() {
  const StakingPool = await ethers.getContractFactory("StakingPool")
  console.log("Deploying StakingPool...")
  // holesky: 0x4242424242424242424242424242424242424242
  const stakingPool = await upgrades.deployProxy(StakingPool,['0x4242424242424242424242424242424242424242'], { initializer: 'initialize' })
  console.log(await stakingPool.getAddress()," StakingPool(proxy) address")
  const stakingPoolAddress = await stakingPool.getAddress()
  // console.log(await upgrades.erc1967.getImplementationAddress(await stakingPool.getAddress())," getImplementationAddress")
  // console.log(await upgrades.erc1967.getAdminAddress(await stakingPool.getAddress())," getAdminAddress")

  // deploy vault
  const Vault = await ethers.getContractFactory("Vault")
  console.log("Deploying Vault...")
  const vault = await upgrades.deployProxy(Vault,[stakingPoolAddress], { initializer: 'initialize' })
  console.log(await vault.getAddress()," Vault(proxy) address")

  const Voting = await ethers.getContractFactory("Voting")
  console.log("Deploying Voting...")
  const voting = await upgrades.deployProxy(Voting,['600000000000000000', '510000000000000000', 180, 60], { initializer: 'initialize' })

  console.log(await voting.getAddress()," Voting(proxy) address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

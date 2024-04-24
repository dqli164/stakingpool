import { ethers, upgrades } from "hardhat"

async function main() {
  const StakingPool = await ethers.getContractFactory("StakingPool")
  console.log("Deploying StakingPool...")
  // holesky: 0x4242424242424242424242424242424242424242
  const stakingPool = await upgrades.deployProxy(StakingPool,['0x4242424242424242424242424242424242424242'], { initializer: 'initialize' })
  console.log(await stakingPool.getAddress()," StakingPool(proxy) address")
  // console.log(await upgrades.erc1967.getImplementationAddress(await stakingPool.getAddress())," getImplementationAddress")
  // console.log(await upgrades.erc1967.getAdminAddress(await stakingPool.getAddress())," getAdminAddress")

  // deploy vault
  const Vault = await ethers.getContractFactory("Vault")
  console.log("Deploying Vault...")
  const vault = await upgrades.deployProxy(Vault,[await stakingPool.getAddress()], { initializer: 'initialize' })
  console.log(await vault.getAddress()," Vault(proxy) address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

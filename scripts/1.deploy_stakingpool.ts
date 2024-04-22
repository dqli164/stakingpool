import { ethers, upgrades } from "hardhat"

async function main() {

  const StakingPool = await ethers.getContractFactory("StakingPool")
  console.log("Deploying StakingPool...")
  // holesky: 0x4242424242424242424242424242424242424242
  const stakingPool = await upgrades.deployProxy(StakingPool,['0x4242424242424242424242424242424242424242'], { initializer: 'initializer' })

  console.log(await stakingPool.getAddress()," stakingPool(proxy) address")
  // console.log(await upgrades.erc1967.getImplementationAddress(await box.getAddress())," getImplementationAddress")
  // console.log(await upgrades.erc1967.getAdminAddress(await box.getAddress())," getAdminAddress")    
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

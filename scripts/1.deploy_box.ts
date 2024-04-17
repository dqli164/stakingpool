import { ethers, upgrades } from "hardhat"
import { vars } from "hardhat/config"

async function main() {

  const Box = await ethers.getContractFactory("Box")
  console.log("Deploying Box...")
  const box = await upgrades.deployProxy(Box,[42], { initializer: 'store' })

  console.log(await box.getAddress()," box(proxy) address")
  console.log(await upgrades.erc1967.getImplementationAddress(await box.getAddress())," getImplementationAddress")
  console.log(await upgrades.erc1967.getAdminAddress(await box.getAddress())," getAdminAddress")    
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

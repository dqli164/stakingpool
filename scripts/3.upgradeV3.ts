import { ethers } from "hardhat";
import { upgrades } from "hardhat";
import { vars } from "hardhat/config";

const proxyAddress = vars.get("PROXY_ADDRESS")

async function main() {
  console.log(proxyAddress," original Box(proxy) address")
  const BoxV3 = await ethers.getContractFactory("BoxV3")
  console.log("upgrade to BoxV3...")
  const boxV3 = await upgrades.upgradeProxy(proxyAddress, BoxV3)
  console.log(await boxV3.getAddress()," BoxV3 address(should be the same)")

  console.log(await upgrades.erc1967.getImplementationAddress(await boxV3.getAddress())," getImplementationAddress")
  console.log(await upgrades.erc1967.getAdminAddress(await boxV3.getAddress()), " getAdminAddress")    
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

import { ethers, upgrades } from "hardhat";
import { vars } from "hardhat/config";

const proxyAddress = vars.get("PROXY_ADDRESS")
console.log('proxyAddress: ', proxyAddress)

async function main() {
  console.log(proxyAddress," original Box(proxy) address")
  const BoxV2 = await ethers.getContractFactory("BoxV2")
  console.log("upgrade to BoxV2...")
  const boxV2 = await upgrades.upgradeProxy(proxyAddress, BoxV2)
  console.log(await boxV2.getAddress()," BoxV2 address(should be the same)")

  // console.log(await upgrades.erc1967.getImplementationAddress(await boxV2.getAddress())," getImplementationAddress")
  // console.log(await upgrades.erc1967.getAdminAddress(await boxV2.getAddress()), " getAdminAddress")    
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

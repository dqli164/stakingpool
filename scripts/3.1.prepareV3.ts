import { ethers } from "hardhat";
import { upgrades } from "hardhat";
import { vars } from "hardhat/config";

const proxyAddress = vars.get("PROXY_ADDRESS")

async function main() {
  console.log(proxyAddress," original Box(proxy) address")
  const BoxV3 = await ethers.getContractFactory("BoxV3")
  console.log("Preparing upgrade to BoxV3...");
  const boxV3Address = await upgrades.prepareUpgrade(proxyAddress, BoxV3);
  console.log(boxV3Address, " BoxV3 implementation contract address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

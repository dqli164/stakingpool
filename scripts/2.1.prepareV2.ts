import { ethers } from "hardhat";
import { upgrades } from "hardhat";
import { vars } from "hardhat/config";

const proxyAddress = vars.get("PROXY_ADDRESS")

async function main() {
  console.log(proxyAddress," original Box(proxy) address")
  const BoxV2 = await ethers.getContractFactory("BoxV2")
  console.log("Preparing upgrade to BoxV2...");
  const boxV2Address = await upgrades.prepareUpgrade(proxyAddress, BoxV2);
  console.log(boxV2Address, " BoxV2 implementation contract address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

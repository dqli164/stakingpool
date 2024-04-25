import { ethers } from "hardhat";
import { upgrades } from "hardhat";

const proxyAddress = '0x2724f24aeC3E782b98b2106d83FF046662BC107E'

async function main() {
  console.log(proxyAddress," original StakingPool(proxy) address")
  const StakingPoolV2 = await ethers.getContractFactory("StakingPoolV2")
  console.log("Preparing upgrade to StakingPoolV2...");
  const stakingPoolV2 = await upgrades.prepareUpgrade(proxyAddress, StakingPoolV2);
  console.log(stakingPoolV2, " StakingPoolV2 implementation contract address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

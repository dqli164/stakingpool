import { ethers, upgrades } from "hardhat"

async function main() {
  const Voting = await ethers.getContractFactory("Voting")
  console.log("Deploying Voting...")
  const voting = await upgrades.deployProxy(Voting,['600000000000000000', '510000000000000000', 180, 60], { initializer: 'initialize' })

  console.log(await voting.getAddress()," voting(proxy) address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

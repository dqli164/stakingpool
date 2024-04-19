import { ethers, upgrades } from "hardhat"

async function main() {

  const VotingV2 = await ethers.getContractFactory("VotingV2")
  console.log("Deploying VotingV2...")
  const votingV2 = await VotingV2.deploy('600000000000000000', '510000000000000000', 180, 60)

  console.log(await votingV2.getAddress()," VotingV2 address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

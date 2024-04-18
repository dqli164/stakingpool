import { ethers, upgrades } from "hardhat"
import { vars } from "hardhat/config"

async function main() {

  const Voting = await ethers.getContractFactory("VotingV2")
  console.log("Deploying Voting...")
  const voting = await Voting.deploy(Voting, [])

  console.log(await voting.getAddress()," Voting address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

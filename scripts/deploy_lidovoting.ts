import { ethers, upgrades } from "hardhat"
import { vars } from "hardhat/config"

async function main() {

  const Voting = await ethers.getContractFactory("LidoVoting")
  console.log("Deploying Voting...")
  const voting = await Voting.deploy()

  console.log(await voting.getAddress()," Voting address")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

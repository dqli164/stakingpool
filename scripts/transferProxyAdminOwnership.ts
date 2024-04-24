import { ethers, upgrades } from "hardhat";
import { vars } from "hardhat/config";

const proxyAddress = vars.get("PROXY_ADDRESS")
const votingAddress = vars.get("VOTING_ADDRESS")
console.log('PROXY_ADDRESS: ', proxyAddress)
console.log('VOTING_ADDRESS: ', votingAddress)

async function main() {
    await upgrades.admin.transferProxyAdminOwnership(proxyAddress, votingAddress)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

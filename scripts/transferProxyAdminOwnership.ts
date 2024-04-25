import { ethers, upgrades } from "hardhat";

const proxyAddress = '0x2724f24aeC3E782b98b2106d83FF046662BC107E'
const votingAddress = '0xbF1e525aA16e61Be7Fe853abd30BDE5cc4B315b4'
console.log('PROXY_ADDRESS: ', proxyAddress)
console.log('VOTING_ADDRESS: ', votingAddress)

async function main() {
    await upgrades.admin.transferProxyAdminOwnership(proxyAddress, votingAddress)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

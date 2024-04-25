import { ethers, upgrades } from "hardhat";

const proxyAddress = '0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0'
const votingAddress = '0x9A676e781A523b5d0C0e43731313A708CB607508'
console.log('PROXY_ADDRESS: ', proxyAddress)
console.log('VOTING_ADDRESS: ', votingAddress)

async function main() {
    await upgrades.admin.transferProxyAdminOwnership(proxyAddress, votingAddress)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  networks: {
    holesky: {
      url: "https://rpc.holesky.ethpandaops.io",
      accounts: [ vars.get("HOLESKY_PRIVATE_KEY")]
    },
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${vars.get('ALCHEMY_API_KEY')}`,
      accounts: [vars.get("SEPOLIA_PRIVATE_KEY")]
    }
  }
};

export default config;

import "@nomicfoundation/hardhat-ethers"
import "@nomicfoundation/hardhat-foundry"
import "@nomicfoundation/hardhat-verify"
import "@typechain/hardhat"
import "hardhat-gas-reporter"
import "hardhat-deploy"
import { HardhatConfig, HardhatUserConfig } from "hardhat/types"
import "hardhat-contract-sizer" // npx hardhat size-contracts
import "solidity-coverage"
import "solidity-docgen"

import "./script/hardhat/tasks/mpc-vault.ts"

require("dotenv").config()

//
// NOTE:
// To load the correct .env, you must run this at the root folder (where hardhat.config is located)
//
const MAINNET_URL = process.env.MAINNET_URL || "https://eth-mainnet"
const MAINNET_PRIVATEKEY = process.env.MAINNET_PRIVATEKEY || "0xkey"
const SEPOLIA_URL = process.env.SEPOLIA_URL || "https://eth-sepolia"
const SEPOLIA_PRIVATEKEY = process.env.SEPOLIA_PRIVATEKEY || "0xkey"
const ILIAD_URL = process.env.ILIAD_URL || "https://eth-iliad"
const ILIAD_PRIVATEKEY = process.env.ILIAD_PRIVATEKEY || "0xkey"

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "key"
const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY || "key"


/** @type import('hardhat/config').HardhatUserConfig */
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.23",
      },
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 31337,
    },
    localhost: {
      chainId: 31337,
      url: "http://127.0.0.1:8545/",
    },
    mainnet: {
      chainId: 1,
      url: MAINNET_URL || "",
      accounts: [MAINNET_PRIVATEKEY],
    },
    iliad: {
      chainId: 1513,
      url: ILIAD_URL || "",
      accounts: [ILIAD_PRIVATEKEY],
    },
  },
  // @ts-ignore
  namedAccounts: {
    deployer: {
      default: 0, // here this will by default take the first account as deployer
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    outputFile: "gas-report.txt",
    noColors: true,
    currency: "USD",
    coinmarketcap: COINMARKETCAP_API_KEY,
  },
  mocha: {
    timeout: 20_000,
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
  },
  docgen: {
    outputDir: "./docs",
    pages: "files"
  }
}

export default config

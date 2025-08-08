/* eslint-disable prettier/prettier */
import * as dotenv from "dotenv";

import {HardhatUserConfig, task} from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
// import "@typechain/hardhat";
// import "hardhat-gas-reporter";
// import "solidity-coverage";
// import "@openzeppelin/hardhat-upgrades";
// import "@nomiclabs/hardhat-solpp";
// import "@nomiclabs/hardhat-solhint";
// import "hardhat-laika";

dotenv.config();

const config: HardhatUserConfig = {
  mocha: {
    timeout: 100000000,
  },
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        count: 10000,
      },
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      gas: 2100000,
      gasPrice: 20000000000,
      accounts: {
        mnemonic: process.env.MNEMONIC ?? "",
      },
    },
    mainnet: {
      url: "https://bsc-dataseed1.defibit.io",
      chainId: 56,
      gas: 2100000,
      gasPrice: 20000000000,
      accounts: {mnemonic: process.env.MNEMONIC ?? ""},
    },
  },
  // gasReporter: {
  //   enabled: true,
  //   currency: "USD",
  // },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;

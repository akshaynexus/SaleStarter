require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require('hardhat-log-remover');
require("hardhat-deploy-ethers");
require("hardhat-deploy");
require("hardhat-gas-reporter");
require("@nomicfoundation/hardhat-foundry");

const { mnemonic, AlchemyProjID, EtherscanAPIKey } = require("./secrets.json");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/tvpvfK0VkGRhMdEm9zy8mr1o0WonugfV`,
        gasPrice: 10 * 1e9,
        network_id: 1,
      },
    },
    "bsc-testnet": {
      url: `https://data-seed-prebsc-1-s1.binance.org:8545/`,
      accounts: {
        mnemonic: mnemonic,
      },
    },
    bsc: {
      url: `https://bsc-dataseed3.ninicoin.io/`,
      accounts: {
        mnemonic: mnemonic,
      },
      gasPrice: 10 * 1e9,
    },
    fantom: {
      url: `https://rpcapi.fantom.network/`,
      accounts: {
        mnemonic: mnemonic,
      },
      gasPrice: 90 * 1e9,
    },
  },
  solidity: {
    version: "0.8.3",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: EtherscanAPIKey,
  },
  mocha: {
    timeout: 20000000,
  },
  gasReporter: {
    enabled: false
  }
};

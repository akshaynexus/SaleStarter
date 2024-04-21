// Import required modules
const ethers = require("ethers");
const fs = require("fs");

// Create a random Ethereum wallet
const wallet = ethers.Wallet.createRandom();

// Prepare data for storage
const data = {
  mnemonic: wallet.mnemonic.phrase,
  InfuraProjID: "1d1d1d",
  EtherscanAPIKey: "12313"
};

// Write the data to a JSON file
fs.writeFileSync("secrets.json", JSON.stringify(data, null, 2));

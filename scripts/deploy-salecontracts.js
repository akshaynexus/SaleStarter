// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const SaleFactory = await hre.ethers.getContractFactory("SaleFactory");
  const SaleData = await hre.ethers.getContractFactory("SaleData");
  saleFactory = await SaleFactory.deploy();
  
  saleData = await SaleData.deploy(saleFactory.address);
  const BaseSale = await ethers.getContractFactory("BaseSale");
  baseSale = await BaseSale.deploy();

  await saleFactory.setBaseSale(baseSale.address);
  await greeter.deployed();

  console.log("Greeter deployed to:", greeter.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

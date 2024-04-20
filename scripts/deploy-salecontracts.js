const hre = require("hardhat");

async function main() {
    await hre.run("compile");

    const SaleFactory = await hre.ethers.getContractFactory("SaleFactory");
    const saleFactory = await SaleFactory.deploy();
    await saleFactory.deployed();
    console.log("SaleFactory deployed to:", saleFactory.address);

    const SaleData = await hre.ethers.getContractFactory("SaleData");
    const saleData = await SaleData.deploy(saleFactory.address);
    await saleData.deployed();
    console.log("SaleData deployed to:", saleData.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

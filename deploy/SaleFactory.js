module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
    const { deploy } = deployments

    const { deployer } = await getNamedAccounts()


    const  saleFactory  = await deploy("SaleFactory", {
      from: deployer,
      args: [],
      log: true,
      deterministicDeployment: false
    })
    await deploy("SaleData", {
        from: deployer,
        args: [saleFactory.address],
        log: true,
        deterministicDeployment: false
    })

  }

  module.exports.tags = ["SaleFactory"]
  module.exports.dependencies = ["BaseSale", "SaleData"]
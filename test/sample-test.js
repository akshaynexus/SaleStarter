const { expect } = require("chai");
const { ethers } = require("hardhat");
const hre = require("hardhat");

ZERO_ADDRESS = "";
describe("SaleFactory", function () {
  let saleFactory,saleData, baseSale, tokenMockForSale, mockSale;

  let owner, addr1, addr2, addrs;
  let buyerWallets = [];

  let signers;

  beforeEach(async function () {
    const SaleFactory = await ethers.getContractFactory("SaleFactory");
    const SaleData = await ethers.getContractFactory("SaleData");

    buyerWallets = await ethers.getSigners();
    owner = buyerWallets[0];
    // runs before each test in this block
    saleFactory = await SaleFactory.deploy();
    await saleFactory.deployed();
    saleData = await SaleData.deploy(saleFactory.address);
    await saleData.deployed()
    //Expect fee to be 2%
    expect(await saleFactory.getETHFee()).to.equal(2 * 100);
    //Expect sale owner to be fee receiver
    expect(await saleFactory.feeReceiver()).to.equal(await saleFactory.owner());

    const BaseSale = await ethers.getContractFactory("BaseSale");
    baseSale = await BaseSale.deploy();

    await baseSale.deployed();
    await saleFactory.setBaseSale(baseSale.address);
    expect(await saleFactory.baseSale()).to.equal(baseSale.address);

    const BurnableToken = await ethers.getContractFactory("BurnableToken");
    tokenMockForSale = await BurnableToken.deploy("TestToken", "TSX");
    await tokenMockForSale.deployed();
    //Approve sale factory to spend tokens to make sale
    await tokenMockForSale.approve(
      saleFactory.address,
      hre.ethers.utils.parseEther("100000")
    );
    pricePerETHBuy = 5;
    priceListing = 2;
    saleParams = [
      tokenMockForSale.address,
      await hre.ethers.utils.parseEther("1"), //Max Buy
      await hre.ethers.utils.parseEther("3"), //SoftCap
      await hre.ethers.utils.parseEther("5"), //Hardcap
      pricePerETHBuy, //Sale price per ETH
      priceListing, //Listing price per eth
      0, //LP unlock time
      Math.round(Date.now() / 1000) + 6000,
      "", //Details json,we leave this blank
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", //Uniswap router
      owner.address, //Creator is autofilled
      20 * 100, // 20% cut to deployer
    ];
    mockSaleAddress = await saleFactory.callStatic.deploySale(saleParams);
    mockSale = await saleFactory.deploySale(saleParams);
    mockSale = await ethers.getContractAt("BaseSale", mockSaleAddress);
    allSales = await saleFactory.getAllSales();
    //  expect(await mockSale.saleConfig()).to.equal(saleParams);
    expect(allSales.length).to.equal(1);
  });

  it("Should get enough allocation per eth", async function () {
    //Send some eth from another account once presale starts
    //Start presale
    await mockSale.forceStartSale();
    for (let i = 1; i < 4; i++) {
      //Buy it up with different wallets
      await buyerWallets[i].sendTransaction({
        to: mockSale.address,
        value: ethers.utils.parseEther("1"),
      });
    }

    //Make sure we got allocated enough
    expect(
      await mockSale.calculateTokensClaimable(ethers.utils.parseEther("1"))
    ).to.equal(ethers.utils.parseEther("5"));
    //Finalize sale after hardcap is close
    mockSale.finalize();
    //Claim and make sure we get enough on claim
    for (let i = 1; i < 4; i++) {
      //Claim them all
      await mockSale.connect(buyerWallets[i]).claimTokens();
      //Check we got enough
      expect(
        await tokenMockForSale.balanceOf(buyerWallets[i].address)
      ).to.equal(ethers.utils.parseEther("5"));
      //User shouldnt be able to claim refund after they claim tokens
      expect(mockSale.connect(buyerWallets[i]).getRefund()).to.be.revertedWith(
        "Tokens already claimed"
      );
      //User shouldnt be able to claim tokens again after they claim tokens
      expect(
        mockSale.connect(buyerWallets[i]).claimTokens()
      ).to.be.revertedWith("Tokens already claimed");
    }
    // //Check that current listing price is correct
    // expect()
  });

  it("Should get refund if sale doesnt pass softcap", async function () {
    //Fill it lesser than softcap
    for (let i = 1; i < 4; i++) {
      //Buy it up with different wallets
      await buyerWallets[i].sendTransaction({
        to: mockSale.address,
        value: ethers.utils.parseEther("0.1"),
      });
      let sales = await saleData.getSalesUserIsIn(buyerWallets[i].address)
      //Check that we get the address registered to factory
      expect(sales[0]).to.equal(mockSale.address)
      expect(sales.length).to.equal(1)
    }
    //Call refund and get back eth since it didnt pass softcap
    for (let i = 1; i < 4; i++) {
      let startBal = await ethers.provider.getBalance(buyerWallets[i].address);
      startBal = parseFloat(startBal.toString());
      await mockSale.connect(buyerWallets[i]).getRefund();
      // let endBal = await ethers.provider.getBalance(buyerWallets[i].address);
      // endBal = parseFloat(endBal.toString());
      // expect(endBal - startBal).to.equal(
      //   parseFloat(ethers.utils.parseEther("1").toString())
      // );
    }
    //User shouldnt be able to claim refund again
    for (let i = 1; i < 4; i++) {
      expect(mockSale.connect(buyerWallets[i]).getRefund()).to.be.revertedWith(
        "Refund already claimed"
      );
    }
    //Now sudden apes came,we got past hardcap,the original user shouldnt be able to claim tokens after finalization since they already claimed refund
    for (let i = 4; i < 8; i++) {
      await buyerWallets[i].sendTransaction({
        to: mockSale.address,
        value: ethers.utils.parseEther("1"),
      });
    }
    mockSale.finalize();
    //User shouldnt be able to claim tokens if they already claimed refund
    for (let i = 1; i < 4; i++) {
      expect(
        mockSale.connect(buyerWallets[i]).claimTokens()
      ).to.be.revertedWith("Refund was claimed");
    }
    //Users who got in sale should be able to claim tokens
    for (let i = 4; i < 8; i++) {
      mockSale.connect(buyerWallets[i]).claimTokens();
    }
  });
});

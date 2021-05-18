const { expect } = require("chai");
const { ethers } = require("hardhat");
const hre = require("hardhat");

ZERO_ADDRESS = "";
describe("ExtendableTokenLocker", function () {
  let locker, token, spamToken;

  let owner;
  let buyerWallets = [];

  beforeEach(async function () {
    const ExtendableTokenLocker = await ethers.getContractFactory(
      "ExtendableTokenLocker"
    );
    const BurnableToken = await ethers.getContractFactory("BurnableToken");

    buyerWallets = await ethers.getSigners();
    owner = buyerWallets[0];

    token = await BurnableToken.deploy("TestToken", "TSX");
    spamToken = await BurnableToken.deploy("SpamToken", "SPAM");

    const secondsSinceEpoch = Math.round(Date.now() / 1000);

    locker = await ExtendableTokenLocker.deploy(
      token.address,
      owner.address,
      secondsSinceEpoch + 2000
    );
  });

  it("Should be able to transfer beneficiary to a new person", async function () {
    await locker.transferBeneficiary(buyerWallets[1].address);
  });
  it("Should be able to extend the lock", async function () {
    await locker.extendLocktime(1000);
  });
  it("Should not be able to sweep the locked token", async function () {
    expect(locker.sweep(token.address)).to.be.revertedWith(
      "Cant sweep config token"
    );
  });
  it("Should be able to sweep a token which has been sent to contract", async function () {
    await spamToken.transfer(locker.address, 10000);
    await locker.sweep(spamToken.address);
    expect(await spamToken.balanceOf(owner.address)).to.equal(
      await spamToken.totalSupply()
    );
  });
});

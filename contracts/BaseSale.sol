//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "hardhat/console.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISaleFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./libraries/CommonStructures.sol";
import "./ExtendableTokenLocker.sol";

contract BaseSale {
    using SafeERC20 for ERC20;
    using Address for address;
    using Address for address payable;

    bool initialized;
    bool saleForceStarted;
    bool public refundEnabled;
    bool public finalized;

    uint256 public totalRaised;
    uint256 DIVISOR;

    CommonStructures.SaleConfig public saleConfig;
    mapping(address => CommonStructures.UserData) public userData;

    ISaleFactory internal saleSpawner;
    address[] internal contributors;

    IUniswapV2Router02 internal router;
    ERC20 internal token;

    ExtendableTokenLocker public lpLocker;

    modifier onlySaleCreator {
        require(msg.sender == saleConfig.creator, "Caller is not sale creator");
        _;
    }

    modifier onlySaleCreatororFactoryOwner {
        //TODO Replace address(0) with a way to get the factory owner
        require(
            msg.sender == saleConfig.creator ||
                msg.sender == address(saleSpawner) ||
                msg.sender == saleSpawner.owner(),
            "Caller is not sale creator or factory allowed"
        );
        _;
    }

    function getETHAmountToListWith(uint baseValue , uint factoryFee) public view returns (uint256 ETHtoAdd) {
        ETHtoAdd = baseValue - factoryFee;
        if(saleConfig.teamShare != 0)
            ETHtoAdd -= (ETHtoAdd * saleConfig.teamShare) / DIVISOR;
    }

    function getRequiredAllocationOfTokens() public view returns (uint256) {
        uint256 saleTokens = calculateTokensClaimable(saleConfig.hardCap);
        uint256 feeToFactory =
            (saleConfig.hardCap * saleSpawner.getETHFee()) / DIVISOR;
        uint256 ETHtoAdd = getETHAmountToListWith(saleConfig.hardCap, feeToFactory);
        uint256 listingTokens = getTokensToAdd(ETHtoAdd);
        return listingTokens + saleTokens;
    }

    function saleStarted() public view returns (bool) {
        return
            (saleForceStarted || block.timestamp >= saleConfig.startTime) &&
            token.balanceOf(address(this)) >= getRequiredAllocationOfTokens();
    }

    function isSaleOver() public view returns (bool) {
        return totalRaised >= saleConfig.hardCap || finalized;
    }

    function initialize(CommonStructures.SaleConfig calldata saleConfigNew)
        public
    {
        require(!initialized, "Already initialized");
        saleConfig = saleConfigNew;
        router = IUniswapV2Router02(saleConfigNew.router);
        token = ERC20(saleConfig.token);
        if (saleConfigNew.lpUnlockTime > 0)
            lpLocker = new ExtendableTokenLocker(
                token,
                saleConfigNew.creator,
                saleConfigNew.lpUnlockTime
            );
        DIVISOR = 10000;
        saleSpawner = ISaleFactory(msg.sender);
        initialized = true;
    }

    receive() external payable {
        if (msg.sender != address(router)) {
            buyTokens();
        }
    }

    function scaleToTokenAmount(uint input) public view returns (uint) {
        uint toScaleDown = 18 - token.decimals();
        return input / 10 ** toScaleDown;
    }

    function calculateTokensClaimable(uint256 valueIn)
        public
        view
        returns (uint256)
    {
        return scaleToTokenAmount(valueIn) * saleConfig.salePrice;
    }

    function getRemainingContribution() external view returns (uint256) {
        return saleConfig.hardCap - totalRaised;
    }

    function buyTokens() public payable {
        require(saleStarted() && !refundEnabled, "Not started yet");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        //First reduce with how much wed fill the raise
        uint EthToContribute = userDataSender.contributedAmount + msg.value > saleConfig.maxBuy ? msg.value - saleConfig.maxBuy : msg.value;
        //Next reduce it if we would fill hardcap
        EthToContribute = totalRaised + EthToContribute > saleConfig.hardCap ? (totalRaised + EthToContribute) - saleConfig.hardCap :EthToContribute;
        require(EthToContribute > 0);
        //Check if it surpases max buy
        require(
            userDataSender.contributedAmount + EthToContribute <= saleConfig.maxBuy,
            "Exceeds max buy"
        );
        //If this is a new user add to array of contributors
        if (userDataSender.contributedAmount == 0)
            contributors.push(msg.sender);
        //Update contributed amount
        userDataSender.contributedAmount += EthToContribute;
        require(
            totalRaised + EthToContribute <= saleConfig.hardCap,
            "HardCap will be reached"
        );
        //Update total raised
        totalRaised += EthToContribute;
        //Update users tokens they can claim
        userDataSender.tokensClaimable += calculateTokensClaimable(EthToContribute);
        //Refund excess
        if(EthToContribute < msg.value) payable(msg.sender).sendValue(msg.value - EthToContribute);
    }

    function shouldRefundWithBal() public view returns (bool) {
        return address(this).balance > 0 && shouldRefund();
    }

    function shouldRefund() public view returns (bool) {
        return (refundEnabled || totalRaised < saleConfig.hardCap);
    }

    function userEligibleToClaimRefund(address user) public view returns (bool) {
        CommonStructures.UserData storage userDataSender = userData[user];
        return !userDataSender.tokensClaimed && !userDataSender.refundTaken && userDataSender.contributedAmount > 0;
    }

    function getRefund() external {
        require(shouldRefund(),
            "Refunds not enabled or doesnt pass config"
        );
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.tokensClaimed, "Tokens already claimed");
        require(!userDataSender.refundTaken, "Refund already claimed");
        require(userDataSender.contributedAmount > 0, "No contribution");
        userDataSender.refundTaken = true;
        payable(msg.sender).sendValue(userDataSender.contributedAmount);
    }

    function claimTokens() external {
        require(!refundEnabled, "Refunds enabled");
        require(finalized, "Sale not finalized yet");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.tokensClaimed, "Tokens already claimed");
        require(!userDataSender.refundTaken, "Refund was claimed");
        require(userDataSender.tokensClaimable > 0, "No tokens to claim");

        userDataSender.tokensClaimed = true;
        token.safeTransfer(msg.sender, userDataSender.tokensClaimable);
    }

    // Admin only functions
    function enableRefunds() external onlySaleCreatororFactoryOwner {
        refundEnabled = true;
    }

    function forceStartSale() external onlySaleCreatororFactoryOwner {
        saleForceStarted = true;
    }

    function cancelSale() external onlySaleCreatororFactoryOwner {
        refundEnabled = true;
        //Send back tokens to creator of the sale
        token.transfer(saleConfig.creator, token.balanceOf(address(this)));
    }

    function getTokensToAdd(uint ethAmount) public view returns (uint) {
        return scaleToTokenAmount(ethAmount) * saleConfig.listingPrice;
    }

    function finalize() external onlySaleCreatororFactoryOwner {
        uint ETHBudget = totalRaised;
        //Send team their eth
        if (saleConfig.teamShare > 0) {
            uint teamShare= (totalRaised * saleConfig.teamShare) / 10000;
            ETHBudget -= teamShare;
            payable(saleConfig.creator).sendValue(
                teamShare
            );
        }
        //Approve router to spend tokens
        token.safeApprove(address(router), type(uint256).max);
        uint256 feeToFactory =
            (totalRaised * saleSpawner.getETHFee()) / DIVISOR;
        //Send fee to factory
        payable(address(saleSpawner)).sendValue(feeToFactory);
        ETHBudget -= feeToFactory;

        uint256 ETHtoAdd = getETHAmountToListWith(ETHBudget, feeToFactory);
        // console.log("%s",ETHtoAdd);

        require(ETHtoAdd <= address(this).balance,"not enough eth in contract");
        //Add liq as given
        uint256 tokensToAdd = getTokensToAdd(ETHtoAdd);
        router.addLiquidityETH{value: ETHtoAdd}(
            address(token),
            tokensToAdd,
            tokensToAdd,
            ETHtoAdd,
            address(lpLocker) != address(0)
                ? address(lpLocker)
                : saleConfig.creator,
            block.timestamp
        );
        //If we have excess send it to factory
        uint remainETH = address(this).balance;
        if(remainETH > 0) payable(address(saleSpawner)).sendValue(remainETH);
        finalized = true;
    }
}

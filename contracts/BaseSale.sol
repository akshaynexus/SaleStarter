//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISaleFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./libraries/CommonStructures.sol";
import "./ExtendableTokenLocker.sol";

contract BaseSale {
    using SafeERC20 for ERC20;
    using Address for address;
    using Address for address payable;

    uint DIVISOR;

    //This gets the sale config passed from sale factory
    CommonStructures.SaleConfig public saleConfig;
    //Used to track the progress and status of the sale
    CommonStructures.SaleInfo public saleInfo;

    mapping(address => CommonStructures.UserData) public userData;

    ISaleFactory internal saleSpawner;
    address[] internal contributors;

    IUniswapV2Router02 internal router;
    ERC20 internal token;
    ERC20 internal fundingToken;

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
    //Primary sale data getters
    function isETHSale() public view returns (bool) {
        return address(fundingToken) == address(0);
    }

    function saleStarted() public view returns (bool) {
        return
            (saleInfo.saleForceStarted || block.timestamp >= saleConfig.startTime) &&
            token.balanceOf(address(this)) >= getRequiredAllocationOfTokens();
    }

    function isSaleOver() public view returns (bool) {
        return saleInfo.totalRaised >= saleConfig.hardCap || saleInfo.finalized;
    }

    //Primary allocation and token amount calculation functions
    function scaleToTokenAmount(uint input) public view returns (uint) {
        uint fundingDecimals = getFundingDecimals();
        if(fundingDecimals == 18) return input;
        uint toScaleDown = getFundingDecimals() - token.decimals();
        return input / 10 ** toScaleDown;
    }

    function getFundingDecimals() public view returns (uint) {
        if(isETHSale()) return 18;
        else return fundingToken.decimals();
    }

    function calculateTokensClaimable(uint valueIn)
        public
        view
        returns (uint)
    {
        return scaleToTokenAmount(valueIn) * saleConfig.salePrice;
    }

    function getTokensToAdd(uint ethAmount) public view returns (uint) {
        return scaleToTokenAmount(ethAmount) * saleConfig.listingPrice;
    }

    function getRequiredAllocationOfTokens() public view returns (uint) {
        uint saleTokens = calculateTokensClaimable(saleConfig.hardCap);
        uint feeToFactory =
            (saleConfig.hardCap * saleSpawner.getETHFee()) / DIVISOR;
        uint ETHBudget = getAmountToListWith(saleConfig.hardCap, feeToFactory);
        uint listingTokens = getTokensToAdd(ETHBudget);
        return listingTokens + saleTokens;
    }

    function getAmountToListWith(uint baseValue , uint factoryFee) public view returns (uint ETHBudget) {
        ETHBudget = baseValue - factoryFee;
        if(saleConfig.teamShare != 0)
            ETHBudget -= (ETHBudget * saleConfig.teamShare) / DIVISOR;
    }

    //User views to get status and remain alloc
    function getRemainingContribution() external view returns (uint) {
        return saleConfig.hardCap - saleInfo.totalRaised;
    }

    function getFundingBalance() public view returns (uint) {
        if(isETHSale()) return address(this).balance;
        return fundingToken.balanceOf(address(this));
    }

    function shouldRefundWithBal() public view returns (bool) {
        return getFundingBalance() > 0 && shouldRefund();
    }

    function shouldRefund() public view returns (bool) {
        return (saleInfo.refundEnabled || saleInfo.totalRaised < saleConfig.hardCap);
    }

    function userEligibleToClaimRefund(address user) public view returns (bool) {
        CommonStructures.UserData storage userDataSender = userData[user];
        return !userDataSender.tokensClaimed && !userDataSender.refundTaken && userDataSender.contributedAmount > 0;
    }

    function initialize(CommonStructures.SaleConfig calldata saleConfigNew)
        public
    {
        require(!saleInfo.initialized, "Already initialized");
        saleConfig = saleConfigNew;
        router = IUniswapV2Router02(saleConfigNew.router);
        token = ERC20(saleConfig.token);
        if (saleConfigNew.lpUnlockTime > 0)
            lpLocker = new ExtendableTokenLocker(
                //TODO get pair token here
                token,
                saleConfigNew.creator,
                saleConfigNew.lpUnlockTime
            );
        DIVISOR = 10000;
        saleSpawner = ISaleFactory(msg.sender);
        if (saleConfigNew.fundingToken != address(0))
            fundingToken = ERC20(saleConfigNew.fundingToken);
        saleInfo.initialized = true;
    }

    receive() external payable {
        if (msg.sender != address(router)) {
            buyTokens();
        }
    }

    function buyTokens() public payable {
        require(isETHSale(),"This sale does not accept ETH");
        require(saleStarted() && !saleInfo.refundEnabled, "Not started yet");
        _handlePurchase(msg.sender, msg.value);
    }

    function _handlePurchase(address user, uint value) internal {
        CommonStructures.UserData storage userDataSender = userData[user];
        //First reduce with how much wed fill the raise
        uint FundsToContribute = userDataSender.contributedAmount + value > saleConfig.maxBuy ? value - saleConfig.maxBuy : value;
        //Next reduce it if we would fill hardcap
        FundsToContribute = saleInfo.totalRaised + FundsToContribute > saleConfig.hardCap ? (saleInfo.totalRaised + FundsToContribute) - saleConfig.hardCap :FundsToContribute;
        require(FundsToContribute > 0,"No remaining limit");
        //Check if it surpases max buy
        require(
            userDataSender.contributedAmount + FundsToContribute <= saleConfig.maxBuy,
            "Exceeds max buy"
        );
        //If this is a new user add to array of contributors
        if (userDataSender.contributedAmount == 0)
            contributors.push(user);
        //Update contributed amount
        userDataSender.contributedAmount += FundsToContribute;
        require(
            saleInfo.totalRaised + FundsToContribute <= saleConfig.hardCap,
            "HardCap will be reached"
        );
        //Update total raised
        saleInfo.totalRaised += FundsToContribute;
        //Update users tokens they can claim
        userDataSender.tokensClaimable += calculateTokensClaimable(FundsToContribute);
        //Refund excess
        if(FundsToContribute < value) _handleExcessRefund(user, value - FundsToContribute);
    }

    function _handleExcessRefund(address user, uint value) internal {
        if(isETHSale())
            payable(user).sendValue(value);
        else
            fundingToken.safeTransfer(user,value);
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
        require(!saleInfo.refundEnabled, "Refunds enabled");
        require(saleInfo.finalized, "Sale not finalized yet");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.tokensClaimed, "Tokens already claimed");
        require(!userDataSender.refundTaken, "Refund was claimed");
        require(userDataSender.tokensClaimable > 0, "No tokens to claim");

        userDataSender.tokensClaimed = true;
        token.safeTransfer(msg.sender, userDataSender.tokensClaimable);
    }

    // Admin only functions
    function enableRefunds() external onlySaleCreatororFactoryOwner {
        saleInfo.refundEnabled = true;
    }

    function forceStartSale() external onlySaleCreatororFactoryOwner {
        saleInfo.saleForceStarted = true;
    }

    function cancelSale() external onlySaleCreatororFactoryOwner {
        saleInfo.refundEnabled = true;
        //Send back tokens to creator of the sale
        token.transfer(saleConfig.creator, token.balanceOf(address(this)));
    }

    function finalize() external onlySaleCreatororFactoryOwner {
        require(!saleInfo.finalized,"Sale already finalized");
        //Set this early to prevent reentrancy
        saleInfo.finalized = true;
    
        uint ETHBudget = saleInfo.totalRaised;
        //Send team their eth
        if (saleConfig.teamShare > 0) {
            uint teamShare= (saleInfo.totalRaised * saleConfig.teamShare) / DIVISOR;
            ETHBudget -= teamShare;
            payable(saleConfig.creator).sendValue(
                teamShare
            );
        }
        //Approve router to spend tokens
        token.safeApprove(address(router), type(uint).max);
        uint feeToFactory =
            (saleInfo.totalRaised * saleSpawner.getETHFee()) / DIVISOR;
        //Send fee to factory
        payable(address(saleSpawner)).sendValue(feeToFactory);
        ETHBudget -= feeToFactory;

        require(ETHBudget <= getFundingBalance(),"not enough eth in contract");
        //Add liq as given
        uint tokensToAdd = getTokensToAdd(ETHBudget);
        router.addLiquidityETH{value: ETHBudget}(
            address(token),
            tokensToAdd,
            tokensToAdd,
            ETHBudget,
            address(lpLocker) != address(0)
                ? address(lpLocker)
                : saleConfig.creator,
            block.timestamp
        );
        //If we have excess send it to factory
        uint remain = getFundingBalance();
        if(remain > 0) _handleExcessRefund(address(saleSpawner), remain);
        //If we have excess tokens after finalization send that to the creator
        uint requiredTokens = getRequiredAllocationOfTokens();
        uint remainToken = token.balanceOf(address(this));
        if (remainToken > requiredTokens) token.safeTransfer(saleConfig.creator,remainToken - requiredTokens);
    }
}

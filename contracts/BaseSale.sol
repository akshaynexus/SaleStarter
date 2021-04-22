//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISaleFactory.sol";

import "./libraries/CommonStructures.sol";
import "./ExtendableTokenLocker.sol";

contract BaseSale {

    using SafeERC20 for IERC20;
    using Address for address;
    using Address for address payable;

    bool initialized;
    bool saleForceStarted;
    bool refundEnabled;
    bool public finalized;
    uint public totalRaised;
    uint DIVISOR = 10000;

    CommonStructures.SaleConfig                     public saleConfig;
    mapping (address => CommonStructures.UserData)  public userData;

    ISaleFactory internal saleSpawner;
    address[] internal contributors;

    IUniswapV2Router02 internal router;
    IERC20 internal token;

    ExtendableTokenLocker public lpLocker;

    modifier onlySaleCreator {
        require(msg.sender == saleConfig.creator,"Caller is not sale creator");
        _;
    }

    modifier onlySaleCreatororFactoryOwner {
        //TODO Replace address(0) with a way to get the factory owner
        require(msg.sender == saleConfig.creator || msg.sender == address(saleSpawner) || msg.sender == saleSpawner.owner(),"Caller is not sale creator or factory allowed");
        _;
    }

    function saleStarted() public view returns (bool) {
        return saleForceStarted || block.timestamp >= saleConfig.startTime;
    }

    function isSaleOver() public view returns (bool) {
        return totalRaised >= saleConfig.hardCap || finalized;
    }

    function initialize(CommonStructures.SaleConfig calldata saleConfigNew) public {
        require(!initialized,"Already initialized");
        saleConfig = saleConfigNew;
        router = IUniswapV2Router02(saleConfigNew.router);
        token = IERC20(saleConfig.token);
        if(saleConfigNew.lpUnlockTime > 0)
            lpLocker = new ExtendableTokenLocker(token,saleConfigNew.creator, saleConfigNew.lpUnlockTime);
        saleSpawner = ISaleFactory(msg.sender);
        initialized = true;

    }

    receive() external payable {
        if(msg.sender != address(router)) {
            buyTokens();
        }
    }

    function calculateTokensClaimable(uint valueIn) public view returns (uint){
        //Sale price = (Tokens per ETH * 1e18) / tokens decimals
        return valueIn * saleConfig.salePrice;
    }

    function getRemainingContribution() external view returns (uint) {
        return saleConfig.hardCap - totalRaised;
    }

    function buyTokens() public payable {
        require(saleStarted() && !refundEnabled,"Not started yet");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        //Check if it surpases max buy
        require(userDataSender.contributedAmount + msg.value <= saleConfig.maxBuy,"Exceeds max buy");
        //If this is a new user add to array of contributors
        if(userDataSender.contributedAmount == 0) contributors.push(msg.sender);
        //Update contributed amount
        userDataSender.contributedAmount += msg.value;
        require(totalRaised + msg.value <= saleConfig.hardCap,"HardCap will be reached");
        //Update total raised
        totalRaised += msg.value;
        //Update users tokens they can claim
        userDataSender.tokensClaimable += calculateTokensClaimable(msg.value);
    }

    function getRefund() external {
        require(refundEnabled || totalRaised < saleConfig.hardCap,"Refunds not enabled or doesnt pass config");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.refundTaken,"Refund already claimed");
        require(userDataSender.contributedAmount > 0,"No contribution");
        userDataSender.refundTaken = true;
        payable(msg.sender).sendValue(userDataSender.contributedAmount);
    }

    function  claimTokens() external{
        require(!refundEnabled,"Refunds enabled");
        require(finalized,"Sale not finalized yet");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.tokensClaimed,"Tokens already claimed");
        require(!userDataSender.refundTaken,"Refund was claimed");
        require(userDataSender.tokensClaimable > 0,"No tokens to claim");
        userDataSender.tokensClaimed = true;
        token.safeTransfer(msg.sender, userDataSender.tokensClaimable);
    }

    // Admin only functions
    function enableRefunds() external onlySaleCreatororFactoryOwner {
        refundEnabled = true;
    }

    function forceStartSale() external onlySaleCreatororFactoryOwner{
        saleForceStarted = true;
    }

    function getTokensToAdd(uint value) public view returns (uint) {
        //Listing price = (Tokens per ETH * 1e18) / tokens decimals
        return value * saleConfig.listingPrice;
    }

    function finalize() external onlySaleCreatororFactoryOwner {
        //Send team their eth
        if(saleConfig.teamShare >0) {
            payable(saleConfig.creator).sendValue((totalRaised * saleConfig.teamShare) / 10000);
        }
        //Approve router to spend tokens
        token.safeApprove(address(router), type(uint256).max);
        uint feeToFactory = (totalRaised * saleSpawner.getETHFee()) / DIVISOR;
        uint ETHtoAdd = totalRaised - feeToFactory;
        //Add liq as given
        uint tokensToAdd = getTokensToAdd(ETHtoAdd);
        router.addLiquidityETH{value : ETHtoAdd}(address(token), tokensToAdd, tokensToAdd, ETHtoAdd, address(lpLocker) != address(0) ? address(lpLocker) : saleConfig.creator, block.timestamp);
        finalized = true;
    }

}
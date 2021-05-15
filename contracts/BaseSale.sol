//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISaleFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libraries/CommonStructures.sol";
import "./ExtendableTokenLocker.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
}

contract BaseSale is ReentrancyGuard{
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
    IWETH internal weth;

    ExtendableTokenLocker public lpLocker;

    event Contributed(address user,uint amount);
    event TokensClaimed(address user,uint amount);
    event ExcessRefunded(address user,uint amount);
    event Refunded(address user,uint amount);
    event TeamShareSent(address user,uint amount);
    event FactoryFeeSent(uint amount);
    event Finalized();

    modifier onlySaleCreator {
        require(msg.sender == saleConfig.creator, "Caller is not sale creator");
        _;
    }

    modifier onlySaleCreatororFactoryOwner {
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
        uint FundingBudget = getAmountToListWith(saleConfig.hardCap, feeToFactory);
        uint listingTokens = getTokensToAdd(FundingBudget);
        return listingTokens + saleTokens;
    }

    function getAmountToListWith(uint baseValue , uint factoryFee) public view returns (uint FundingBudget) {
        FundingBudget = baseValue - factoryFee;
        if(saleConfig.teamShare != 0)
            FundingBudget -= (FundingBudget * saleConfig.teamShare) / DIVISOR;
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
                //TODO get pair token here as token to lock than the Sale token
                token,
                saleConfigNew.creator,
                saleConfigNew.lpUnlockTime
            );
        DIVISOR = 10000;
        saleSpawner = ISaleFactory(msg.sender);
        if (saleConfigNew.fundingToken != address(0))
            fundingToken = ERC20(saleConfigNew.fundingToken);
        weth = IWETH(router.WETH());
        saleInfo.initialized = true;
    }

    receive() external payable {
        if (msg.sender != address(router)) {
            buyTokens();
        }
    }

    function buyTokens() public payable nonReentrant {
        require(isETHSale(),"This sale does not accept ETH");
        require(saleStarted() && !saleInfo.refundEnabled, "Not started yet");
        _handlePurchase(msg.sender, msg.value);
    }

    function contributeTokens(uint _amount) public nonReentrant {
        require(!isETHSale(),"This sale accepts ETH, use buyTokens instead");
        require(saleStarted() && !saleInfo.refundEnabled, "Not started yet");
        //Transfer funding token to this address
        fundingToken.safeTransferFrom(msg.sender,address(this), _amount);
        _handlePurchase(msg.sender, _amount);
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
        if(FundsToContribute < value){
            uint amountToRefund = value - FundsToContribute;
            _handleFundingTransfer(user, amountToRefund);
            emit ExcessRefunded(user, amountToRefund);
        }
        emit Contributed(user, value);
    }

    function _handleFundingTransfer(address user, uint value) internal {
        if(isETHSale())
            payable(user).sendValue(value);
        else
            fundingToken.safeTransfer(user,value);
    }

    function getRefund() external nonReentrant {
        require(shouldRefund(),
            "Refunds not enabled or doesnt pass config"
        );
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.tokensClaimed, "Tokens already claimed");
        require(!userDataSender.refundTaken, "Refund already claimed");
        require(userDataSender.contributedAmount > 0, "No contribution");
        userDataSender.refundTaken = true;
        _handleFundingTransfer(msg.sender, userDataSender.contributedAmount);
        //If this refund was called when refund was not enabled and under hardcap reduce from total raised
        if(saleInfo.totalRaised < saleConfig.hardCap && !saleInfo.refundEnabled) {
            saleInfo.totalRaised -= userDataSender.contributedAmount;
        }
        emit Refunded(msg.sender, userDataSender.contributedAmount);
    }

    function claimTokens() external nonReentrant {
        require(!saleInfo.refundEnabled, "Refunds enabled");
        require(saleInfo.finalized, "Sale not finalized yet");
        CommonStructures.UserData storage userDataSender = userData[msg.sender];
        require(!userDataSender.tokensClaimed, "Tokens already claimed");
        require(!userDataSender.refundTaken, "Refund was claimed");
        require(userDataSender.tokensClaimable > 0, "No tokens to claim");

        userDataSender.tokensClaimed = true;
        token.safeTransfer(msg.sender, userDataSender.tokensClaimable);
        emit TokensClaimed(msg.sender,userDataSender.tokensClaimable);
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

    function addLiquidity(uint fundingAmount, uint tokenAmount, bool fETH) internal {
        //If this is ETH,deposit in WETH from contract
        if (fETH) {
            weth.deposit{value:fundingAmount}();
            weth.approve(address(router),fundingAmount);
        }

        //Then call addliquidity with token0 and weth and token1 as the token,so that we dont rely on addLiquidityETH
        router.addLiquidity(
            fETH ? address(weth) : address(fundingToken),
            address(token),
            fundingAmount,
            tokenAmount,
            fundingAmount,
            tokenAmount,
            address(lpLocker) != address(0)
                ? address(lpLocker)
                : saleConfig.creator,
            block.timestamp
        );
    }

    //NOTE: Do not add liq before sale finalizes or finalize will fail if price on pair is different from the configured listing price
    function finalize() external onlySaleCreatororFactoryOwner nonReentrant {
        require(saleInfo.totalRaised > saleConfig.softCap,"Raise amount didnt pass softcap");
        require(!saleInfo.finalized,"Sale already finalized");
        uint FundingBudget = saleInfo.totalRaised;
        //Send team their eth
        if (saleConfig.teamShare > 0) {
            uint teamShare= (saleInfo.totalRaised * saleConfig.teamShare) / DIVISOR;
            FundingBudget -= teamShare;
            _handleFundingTransfer(saleConfig.creator,
                teamShare
            );
            emit TeamShareSent(saleConfig.creator, teamShare);
        }
        //Approve router to spend tokens
        token.safeApprove(address(router), type(uint).max);
        uint feeToFactory =
            (saleInfo.totalRaised * saleSpawner.getETHFee()) / DIVISOR;
        //Send fee to factory
        _handleFundingTransfer(address(saleSpawner),feeToFactory);
        emit FactoryFeeSent(feeToFactory);
        FundingBudget -= feeToFactory;
        require(FundingBudget <= getFundingBalance(),"not enough in contract");
        //Add liq as given
        uint tokensToAdd = getTokensToAdd(FundingBudget);
        addLiquidity(FundingBudget, tokensToAdd, isETHSale());
        //If we have excess send it to factory
        uint remain = getFundingBalance();
        if(remain > 0) _handleFundingTransfer(address(saleSpawner), remain);
        //If we have excess tokens after finalization send that to the creator
        uint requiredTokens = getRequiredAllocationOfTokens();
        uint remainToken = token.balanceOf(address(this));
        if (remainToken > requiredTokens) token.safeTransfer(saleConfig.creator,remainToken - requiredTokens);
        saleInfo.finalized = true;
        emit Finalized();
    }
}

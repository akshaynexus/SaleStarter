//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/ISaleFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libraries/CommonStructures.sol";
import "./ExtendableTokenLocker.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
}

contract BaseSale is ReentrancyGuard {
    using SafeERC20 for ERC20;
    using SafeERC20 for IERC20;
    using Address for address;
    using Address for address payable;

    uint256 constant DIVISOR = 10000;

    //This gets the sale config passed from sale factory
    CommonStructures.SaleConfig public saleConfig;
    //Used to track the progress and status of the sale
    CommonStructures.SaleInfo public saleInfo;
    //Stores the user data,used to track contribution and refund data
    mapping(address => CommonStructures.UserData) public userData;

    ISaleFactory internal saleSpawner;
    address[] internal contributors;

    IUniswapV2Router02 internal router;

    ERC20 internal token;
    ERC20 internal fundingToken;
    IWETH internal weth;

    ExtendableTokenLocker public lpLocker;

    event Contributed(address user, uint256 amount);
    event TokensClaimed(address user, uint256 amount);
    event ExcessRefunded(address user, uint256 amount);
    event Refunded(address user, uint256 amount);
    event TeamShareSent(address user, uint256 amount);
    event FactoryFeeSent(uint256 amount);
    event SentToken(address token, uint256 amount);
    event Finalized();

    modifier onlySaleCreator {
        require(msg.sender == saleConfig.creator, "Caller is not sale creator");
        _;
    }

    modifier onlySaleFactoryOwner {
        require(msg.sender == saleSpawner.owner(), "Caller is not sale creator or factory allowed");
        _;
    }

    modifier onlySaleCreatororFactoryOwner {
        require(
            msg.sender == saleConfig.creator || msg.sender == address(saleSpawner) || msg.sender == saleSpawner.owner(),
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
    function scaleToTokenAmount(uint256 input) public view returns (uint256) {
        uint256 fundingDecimals = getFundingDecimals();
        if (fundingDecimals == 18) return input;
        uint256 toScaleDown = getFundingDecimals() - token.decimals();
        return input / 10**toScaleDown;
    }

    function getFundingDecimals() public view returns (uint256) {
        if (isETHSale()) return 18;
        else return fundingToken.decimals();
    }

    function calculateTokensClaimable(uint256 valueIn) public view returns (uint256) {
        return scaleToTokenAmount(valueIn) * saleConfig.salePrice;
    }

    function getTokensToAdd(uint256 ethAmount) public view returns (uint256) {
        return scaleToTokenAmount(ethAmount) * saleConfig.listingPrice;
    }

    //This returns amount of tokens we need to allocate based on sale config
    function getRequiredAllocationOfTokens() public view returns (uint256) {
        uint256 saleTokens = calculateTokensClaimable(saleConfig.hardCap);
        uint256 feeToFactory = (saleConfig.hardCap * saleSpawner.getETHFee()) / DIVISOR;
        uint256 FundingBudget = getAmountToListWith(saleConfig.hardCap, feeToFactory);
        uint256 listingTokens = getTokensToAdd(FundingBudget);
        return listingTokens + saleTokens;
    }

    //This is used for token allocation calc from the saleconfig
    function getAmountToListWith(uint256 baseValue, uint256 factoryFee) public view returns (uint256 FundingBudget) {
        FundingBudget = baseValue - factoryFee;
        if (saleConfig.teamShare != 0) FundingBudget -= (FundingBudget * saleConfig.teamShare) / DIVISOR;
    }

    //User views to get status and remain alloc
    function getRemainingContribution() external view returns (uint256) {
        return saleConfig.hardCap - saleInfo.totalRaised;
    }

    //Gets how much of the funding source balance is in contract
    function getFundingBalance() public view returns (uint256) {
        if (isETHSale()) return address(this).balance;
        return fundingToken.balanceOf(address(this));
    }

    //Used to see if a sale has remaining balance that a user could claim refunds from
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

    //This creates and returns the pair for the sale if it doesnt exist
    function createPair(address baseToken, address saleToken) internal returns (IERC20) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        address curPair = factory.getPair(baseToken, saleToken);
        if (curPair != address(0)) return IERC20(curPair);
        return IERC20(factory.createPair(baseToken, saleToken));
    }

    //This is the initializer so that minimal proxy clones can be initialized once
    function initialize(CommonStructures.SaleConfig calldata saleConfigNew) public {
        require(!saleInfo.initialized, "Already initialized");
        saleConfig = saleConfigNew;
        router = IUniswapV2Router02(saleConfigNew.router);
        token = ERC20(saleConfig.token);
        saleSpawner = ISaleFactory(msg.sender);
        if (saleConfigNew.fundingToken != address(0)) fundingToken = ERC20(saleConfigNew.fundingToken);
        weth = IWETH(router.WETH());
        if (saleConfigNew.lpUnlockTime > 0)
            lpLocker = new ExtendableTokenLocker(
                createPair(address(fundingToken) == address(0) ? address(weth) : address(saleConfigNew.fundingToken), address(token)),
                saleConfigNew.creator,
                saleConfigNew.lpUnlockTime
            );
        saleInfo.initialized = true;
    }

    receive() external payable {
        if (msg.sender != address(router)) {
            buyTokens();
        }
    }

    //Upon receiving ETH This is called
    function buyTokens() public payable nonReentrant {
        require(isETHSale(), "This sale does not accept ETH");
        require(saleStarted() && !saleInfo.refundEnabled, "Not started yet");
        _handlePurchase(msg.sender, msg.value);
    }

    //This function is used to contribute to sales that arent taking eth as contrib
    function contributeTokens(uint256 _amount) public nonReentrant {
        require(!isETHSale(), "This sale accepts ETH, use buyTokens instead");
        require(saleStarted() && !saleInfo.refundEnabled, "Not started yet");
        //Transfer funding token to this address
        fundingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _handlePurchase(msg.sender, _amount);
    }

    function calculateLimitForUser(uint256 contributedAmount, uint256 value) internal view returns (uint256 limit) {
        limit = saleInfo.totalRaised + value > saleConfig.hardCap ? (saleInfo.totalRaised + value) - saleConfig.hardCap : value;
        limit = (contributedAmount + limit) > saleConfig.maxBuy ? Math.min(saleConfig.maxBuy, this.getRemainingContribution()) : limit;
    }

    function _handlePurchase(address user, uint256 value) internal {
        //First check tx price,if higher than max gas price and gas limits are enabled reject it
        require(saleSpawner.checkTxPrice(tx.gasprice), "Above gas price limit");
        CommonStructures.UserData storage userDataSender = userData[user];
        uint256 FundsToContribute = calculateLimitForUser(userDataSender.contributedAmount, value);
        if (FundsToContribute == 0) {
            //If there is no balance possible just refund it all
            _handleFundingTransfer(user, value);
            emit ExcessRefunded(user, value);
            return;
        }
        //Check if it surpases max buy
        require(userDataSender.contributedAmount + FundsToContribute <= saleConfig.maxBuy, "Exceeds max buy");
        //Check if it passes hardcap
        require(saleInfo.totalRaised + FundsToContribute <= saleConfig.hardCap, "HardCap will be reached");
        //If this is a new user add to array of contributors
        if (userDataSender.contributedAmount == 0) contributors.push(user);
        //Update contributed amount
        userDataSender.contributedAmount += FundsToContribute;
        //Update total raised
        saleInfo.totalRaised += FundsToContribute;
        uint256 tokensToAdd = calculateTokensClaimable(FundsToContribute);
        //Update users tokens they can claim
        userDataSender.tokensClaimable += tokensToAdd;
        //Add to total tokens to keep
        saleInfo.totalTokensToKeep += tokensToAdd;
        //Refund excess
        if (FundsToContribute < value) {
            uint256 amountToRefund = value - FundsToContribute;
            _handleFundingTransfer(user, amountToRefund);
            emit ExcessRefunded(user, amountToRefund);
        }

        emit Contributed(user, value);
    }

    function _handleFundingTransfer(address user, uint256 value) internal {
        if (isETHSale()) payable(user).sendValue(value);
        else fundingToken.safeTransfer(user, value);
    }

    function getRefund() external nonReentrant {
        require(shouldRefund(), "Refunds not enabled or doesnt pass config");

        CommonStructures.UserData storage userDataSender = userData[msg.sender];

        require(!userDataSender.tokensClaimed, "Tokens already claimed");
        require(!userDataSender.refundTaken, "Refund already claimed");
        require(userDataSender.contributedAmount > 0, "No contribution");

        userDataSender.refundTaken = true;
        _handleFundingTransfer(msg.sender, userDataSender.contributedAmount);
        //If this refund was called when refund was not enabled and under hardcap reduce from total raised
        saleInfo.totalRaised -= userDataSender.contributedAmount;
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
        emit TokensClaimed(msg.sender, userDataSender.tokensClaimable);
    }

    // Admin only functions
    function enableRefunds() external onlySaleCreatororFactoryOwner {
        saleInfo.refundEnabled = true;
        saleInfo.totalTokensToKeep = 0;
    }

    function forceStartSale() external onlySaleCreatororFactoryOwner {
        saleInfo.saleForceStarted = true;
    }

    function cancelSale() external onlySaleCreatororFactoryOwner {
        this.enableRefunds();
        //Send back tokens to creator of the sale
        token.transfer(saleConfig.creator, token.balanceOf(address(this)));
    }

    //Recover any tokens thats sent to BaseSale by factory owner
    function recoverTokens(address _token) external onlySaleFactoryOwner {
        IERC20 iToken = IERC20(_token);
        uint256 amount = iToken.balanceOf(address(this));
        iToken.safeTransfer(msg.sender, amount);
        emit SentToken(_token, amount);
    }

    //This function takes care of adding liq to the specified base pair
    function addLiquidity(
        uint256 fundingAmount,
        uint256 tokenAmount,
        bool fETH
    ) internal {
        //If this is ETH,deposit in WETH from contract
        if (fETH) {
            weth.deposit{value: fundingAmount}();
            weth.approve(address(router), fundingAmount);
        }

        //Then call addliquidity with token0 and weth and token1 as the token,so that we dont rely on addLiquidityETH
        router.addLiquidity(
            fETH ? address(weth) : address(fundingToken),
            address(token),
            fundingAmount,
            tokenAmount,
            fundingAmount,
            tokenAmount,
            address(lpLocker) != address(0) ? address(lpLocker) : saleConfig.creator,
            block.timestamp
        );
    }

    //NOTE: Do not add liq before sale finalizes or finalize will fail if price on pair is different from the configured listing price
    //This call finalizes the sale and lists on the uniswap dex (or any other dex given in the router)
    function finalize() external onlySaleCreatororFactoryOwner nonReentrant {
        require(saleInfo.totalRaised > saleConfig.softCap, "Raise amount didnt pass softcap");
        require(!saleInfo.finalized, "Sale already finalized");

        uint256 FundingBudget = saleInfo.totalRaised;

        //Send team their eth
        if (saleConfig.teamShare > 0) {
            uint256 teamShare = (saleInfo.totalRaised * saleConfig.teamShare) / DIVISOR;
            FundingBudget -= teamShare;
            _handleFundingTransfer(saleConfig.creator, teamShare);
            emit TeamShareSent(saleConfig.creator, teamShare);
        }

        //Send fee to factory
        uint256 feeToFactory = (saleInfo.totalRaised * saleSpawner.getETHFee()) / DIVISOR;
        _handleFundingTransfer(address(saleSpawner), feeToFactory);
        emit FactoryFeeSent(feeToFactory);
        FundingBudget -= feeToFactory;

        require(FundingBudget <= getFundingBalance(), "not enough in contract");
        //Approve router to spend tokens
        token.safeApprove(address(router), type(uint256).max);
        //Add liq as given
        uint256 tokensToAdd = getTokensToAdd(FundingBudget);
        addLiquidity(FundingBudget, tokensToAdd, isETHSale());

        //If we have excess send it to factory
        uint256 remain = getFundingBalance();
        if (remain > 0) {
            _handleFundingTransfer(address(saleSpawner), remain);
        }

        //If we have excess tokens after finalization send that to the creator
        uint256 remainToken = token.balanceOf(address(this));
        if (remainToken > saleInfo.totalTokensToKeep) {
            token.safeTransfer(saleConfig.creator, remainToken - saleInfo.totalTokensToKeep);
            require(token.balanceOf(address(this)) == saleInfo.totalTokensToKeep, "we have more leftover");
        }

        saleInfo.finalized = true;
        emit Finalized();
    }
}

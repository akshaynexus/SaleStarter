//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/ISaleFactory.sol";
import "./interfaces/IBaseSale.sol";

import "./ExtendableTokenLocker.sol";

interface IERC20D is IERC20 {
    function decimals() external view returns (uint8);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

contract BaseSale is IBaseSaleWithoutStructures, ReentrancyGuard {
    using SafeERC20 for IERC20D;
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

    IERC20D internal token;
    IERC20D internal fundingToken;
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

    modifier onlySaleCreator() {
        require(msg.sender == saleConfig.creator, "Caller is not sale creator");
        _;
    }

    modifier onlySaleCreatororFactoryOwner() {
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
        return (saleInfo.saleForceStarted || block.timestamp >= saleConfig.startTime)
            && token.balanceOf(address(this)) >= getRequiredAllocationOfTokens();
    }

    function isSaleOver() public view returns (bool) {
        return saleInfo.totalRaised >= saleConfig.hardCap || saleInfo.finalized;
    }

    //Primary allocation and token amount calculation functions
    function scaleToTokenAmount(uint256 input) public view returns (uint256) {
        uint256 fundingDecimals = getFundingDecimals();
        if (fundingDecimals == 18) return input;
        uint256 toScaleDown = getFundingDecimals() - token.decimals();
        return input / 10 ** toScaleDown;
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
    function createPair(address baseToken, address saleToken) internal returns (IERC20D) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        address curPair = factory.getPair(baseToken, saleToken);
        if (curPair != address(0)) return IERC20D(curPair);
        return IERC20D(factory.createPair(baseToken, saleToken));
    }

    //This is the initializer so that minimal proxy clones can be initialized once
    function initialize(CommonStructures.SaleConfig calldata saleConfigNew) public {
        require(!saleInfo.initialized, "Already initialized");
        saleConfig = saleConfigNew;
        router = IUniswapV2Router02(saleConfig.router);
        token = IERC20D(saleConfig.token);
        saleSpawner = ISaleFactory(msg.sender);
        if (saleConfig.fundingToken != address(0)) fundingToken = IERC20D(saleConfig.fundingToken);
        weth = IWETH(router.WETH());
        if (saleConfig.lpUnlockTime > 0) {
            lpLocker = new ExtendableTokenLocker(
                createPair(
                    address(fundingToken) == address(0) ? address(weth) : address(saleConfig.fundingToken),
                    address(token)
                ),
                saleConfig.creator,
                saleConfig.lpUnlockTime
            );
        }
        saleInfo.initialized = true;
    }

    receive() external payable {
        if (msg.sender != address(router)) {
            contribute(msg.value);
        }
    }

    //This function is used to contribute to sales that arent taking eth as contrib
    function contribute(uint256 _amount) public payable nonReentrant {
        require(saleStarted() && !saleInfo.refundEnabled, "Not started yet");
        //Transfer funding token to this address
        if (!isETHSale()) {
            fundingToken.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            _amount = msg.value;
        }
        _handlePurchase(msg.sender, _amount);
    }

    function calculateLimitForUser(uint256 contributedAmount, uint256 value) public view returns (uint256 limit) {
        limit = saleInfo.totalRaised + value > saleConfig.hardCap
            ? (saleInfo.totalRaised + value) - saleConfig.hardCap
            : value;
        limit = (contributedAmount + limit) > saleConfig.maxBuy
            ? Math.min(saleConfig.maxBuy, this.getRemainingContribution())
            : limit;
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

        saleInfo.totalRaised -= userDataSender.contributedAmount;
        saleInfo.totalTokensToKeep -= saleInfo.totalTokensToKeep > 0 ? userDataSender.tokensClaimable : 0;

        userDataSender.refundTaken = true;
        _handleFundingTransfer(msg.sender, userDataSender.contributedAmount);
        userDataSender.contributedAmount = 0;
        //If this refund was called when refund was not enabled and under hardcap reduce from total raised
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
        userDataSender.tokensClaimable = 0;
    }

    // Admin only functions
    function enableRefunds() public onlySaleCreatororFactoryOwner {
        saleInfo.refundEnabled = true;
        saleInfo.totalTokensToKeep = 0;
    }

    function forceStartSale() external onlySaleCreatororFactoryOwner {
        saleInfo.saleForceStarted = true;
    }

    function cancelSale() external onlySaleCreatororFactoryOwner {
        enableRefunds();
        //Send back tokens to creator of the sale
        token.safeTransfer(saleConfig.creator, token.balanceOf(address(this)));
    }

    //Recover any tokens thats sent to BaseSale
    function recoverTokens(address _token) external onlySaleCreatororFactoryOwner {
        require(_token != saleConfig.token, "Cant recover sale token");
        IERC20D iToken = IERC20D(_token);
        uint256 amount = iToken.balanceOf(address(this));
        iToken.safeTransfer(msg.sender, amount);
        emit SentToken(_token, amount);
    }

    //This function takes care of adding liq to the specified base pair
    function addLiquidity(uint256 fundingAmount, uint256 tokenAmount, bool fETH) internal {
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

    // This call finalizes the sale and lists on the uniswap dex (or any other dex given in the router)
    function finalize() external onlySaleCreatororFactoryOwner nonReentrant {
        require(saleInfo.totalRaised > saleConfig.softCap, "Raise amount didnt pass softcap");
        require(!saleInfo.finalized, "Sale already finalized");
        // require(saleInfo.totalRaised >= saleConfig.hardCap,"Didnt go to hardcap");

        uint256 FundingBudget = _handleFactoryFee(_handleTeamShare(saleInfo.totalRaised));

        require(FundingBudget <= getFundingBalance(), "not enough in contract");

        token.safeApprove(address(router), type(uint256).max);
        _addLiquidity(FundingBudget);
        _handleExcess();

        saleInfo.finalized = true;
        emit Finalized();
    }

    /// @dev Handles the team's share of the raised funds.
    /// @param fundingBudget The current funding budget.
    /// @return The updated funding budget after deducting the team's share.
    function _handleTeamShare(uint256 fundingBudget) internal returns (uint256) {
        if (saleConfig.teamShare > 0) {
            uint256 teamShare = (saleInfo.totalRaised * saleConfig.teamShare) / DIVISOR;
            fundingBudget -= teamShare;
            _handleFundingTransfer(saleConfig.creator, teamShare);
            emit TeamShareSent(saleConfig.creator, teamShare);
        }
        return fundingBudget;
    }

    /// @dev Handles the factory fee.
    /// @param fundingBudget The current funding budget.
    /// @return The updated funding budget after deducting the factory fee.
    function _handleFactoryFee(uint256 fundingBudget) internal returns (uint256) {
        uint256 feeToFactory = (saleInfo.totalRaised * saleSpawner.getETHFee()) / DIVISOR;
        fundingBudget -= feeToFactory;
        _handleFundingTransfer(address(saleSpawner), feeToFactory);
        emit FactoryFeeSent(feeToFactory);
        return fundingBudget;
    }

    /// @dev Adds liquidity to the specified DEX.
    /// @param fundingBudget The funding budget for adding liquidity.
    function _addLiquidity(uint256 fundingBudget) internal {
        uint256 tokensToAdd = getTokensToAdd(fundingBudget);
        addLiquidity(fundingBudget, tokensToAdd, isETHSale());
    }

    /// @dev Handles excess funding and tokens after the sale is finalized.
    function _handleExcess() internal {
        // If we have excess funding, send it to the factory
        uint256 remainingFunding = getFundingBalance();
        if (remainingFunding > 0) {
            _handleFundingTransfer(address(saleSpawner), remainingFunding);
        }

        // If we have excess tokens after finalization, send them to the creator
        uint256 remainingTokens = token.balanceOf(address(this));
        if (remainingTokens > saleInfo.totalTokensToKeep) {
            token.safeTransfer(saleConfig.creator, remainingTokens - saleInfo.totalTokensToKeep);
            require(token.balanceOf(address(this)) == saleInfo.totalTokensToKeep, "we have more leftover");
        }
    }
}

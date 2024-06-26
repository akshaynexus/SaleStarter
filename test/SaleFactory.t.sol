// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/SaleFactory.sol";
import "../contracts/SaleData.sol";
import "../contracts/mock/ReentrantToken.sol";

contract SaleFactoryTestV2 is Test {
    SaleFactory public saleFactory;
    SaleData public saleData;
    BaseSale public mockSale;
    BaseSale public mockSaleNew;

    BurnableToken public tokenMockForSale;
    BurnableToken public mistakeToken;

    address public owner;
    address[] public buyerWallets;

    uint256 public pricePerETHBuy;
    uint256 public priceListing;
    CommonStructures.SaleConfig saleParams;
    uint256 constant DIVISOR = 10000;

    function setUp() public {
        vm.createSelectFork("mainnet", 19702169);
        buyerWallets = new address[](11);
        for (uint256 i = 0; i < 11; i++) {
            buyerWallets[i] = address(uint160(i + 1));
        }
        owner = buyerWallets[0];

        vm.startPrank(owner);
        saleFactory = new SaleFactory();
        saleData = new SaleData(address(saleFactory));

        assertEq(saleFactory.getETHFee(), 2 * 100, "Fee should be 2%");
        assertEq(saleFactory.feeReceiver(), saleFactory.owner(), "Sale owner should be the fee receiver");
        assertEq(saleFactory.owner(), owner, "Sale owner is not correct");

        tokenMockForSale = new BurnableToken("TestToken", "TSX");
        mistakeToken = new BurnableToken("sweepToken", "STX");
        tokenMockForSale.approve(address(saleFactory), 100000 ether);
        pricePerETHBuy = 5;
        priceListing = 2;
        saleParams = CommonStructures.SaleConfig({
            token: address(tokenMockForSale),
            fundingToken: address(0),
            maxBuy: 1 ether,
            softCap: 3 ether,
            hardCap: 5 ether,
            salePrice: pricePerETHBuy,
            listingPrice: priceListing,
            startTime: block.timestamp,
            lpUnlockTime: 0,
            detailsJSON: "",
            router: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            creator: owner,
            teamShare: (20 * 100),
            isV3: true
        });

        address payable mockSaleAddress = saleFactory.deploySale(saleParams);
        mockSale = BaseSale(mockSaleAddress);
        vm.stopPrank();
        assertEq(saleFactory.getAllSales().length, 1, "There should be one sale deployed");
    }

    modifier asOwner() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    function _finalizeSale() internal asOwner {
        mockSale.finalize();
    }

    function _forceStartSale() internal asOwner {
        mockSale.forceStartSale();
    }

    function _enableRefund() internal asOwner {
        mockSale.enableRefunds();
    }

    function _finalizeNewsale() internal asOwner {
        mockSaleNew.finalize();
    }

    function contributeToBuy(address buyer, uint256 amount) internal {
        contributeToBuySale(address(mockSale), buyer, amount);
    }

    function contributeToBuySale(address sale, address buyer, uint256 amount) internal {
        vm.deal(buyer, 0);
        vm.deal(buyer, amount);
        vm.startPrank(buyer);
        (bool success, bytes memory data) = address(sale).call{value: amount}("");
        if (!success) {
            if (data.length > 0) {
                // Bubble up the underlying revert reason
                assembly {
                    let ptr := mload(0x40)
                    let size := returndatasize()
                    returndatacopy(ptr, 0, size)
                    revert(ptr, size)
                }
            } else {
                revert("buying tokens failed");
            }
        }
        vm.stopPrank();
    }

    function _fillTheSale(BaseSale sale) internal {
        uint256 ethRequired = sale.getRemainingContribution();

        for (uint256 i = 1; ethRequired >= 0; i++) {
            uint256 amountToBuy = sale.calculateLimitForUser(address(sale).balance, 100 ether);
            if (amountToBuy == 0) return;
            contributeToBuySale(address(sale), buyerWallets[i], amountToBuy);
            console.log("contributed %d eth", amountToBuy);
            ethRequired = sale.getRemainingContribution();
        }
    }

    function testEnoughAllocationPerEth() public {
        _fillTheSale(mockSale);

        assertEq(mockSale.calculateTokensClaimable(1 ether), 5 ether, "Allocation per ETH should be correct");

        _finalizeSale();

        for (uint256 i = 1; i < 6; i++) {
            vm.prank(buyerWallets[i]);
            mockSale.claimTokens();
            assertEq(tokenMockForSale.balanceOf(buyerWallets[i]), 5 ether, "Claimed tokens should be correct");

            vm.expectRevert("Refunds not enabled or doesnt pass config");
            vm.prank(buyerWallets[i]);
            mockSale.getRefund();

            vm.expectRevert("Tokens already claimed");
            vm.prank(buyerWallets[i]);
            mockSale.claimTokens();
        }

        assertEq(tokenMockForSale.balanceOf(address(mockSale)), 0, "Sale contract should have no leftover tokens");
    }

    function testRefundIfSaleDoesNotPassSoftcap() public {
        for (uint256 i = 1; i < 5; i++) {
            contributeToBuy(buyerWallets[i], 0.1 ether);

            address[] memory sales = saleData.getSalesUserIsIn(buyerWallets[i]);
            assertEq(sales[0], address(mockSale), "User should be registered in the sale");
            assertEq(sales.length, 1, "User should be in one sale");
        }
        //Test Call refund and get back eth since it didnt pass softcap
        for (uint256 i = 1; i < 5; i++) {
            uint256 startBal = buyerWallets[i].balance;
            vm.prank(buyerWallets[i]);
            mockSale.getRefund();
            assertEq(buyerWallets[i].balance - startBal, 0.1 ether, "user not refunded");
        }

        for (uint256 i = 1; i < 5; i++) {
            vm.expectRevert("Refund already claimed");
            vm.prank(buyerWallets[i]);
            mockSale.getRefund();
        }

        for (uint256 i = 6; i < 11; i++) {
            contributeToBuy(buyerWallets[i], 1 ether);
        }

        assertEq(mockSale.getRemainingContribution(), 0, "Remaining contribution should be 0");

        _finalizeSale();

        for (uint256 i = 1; i < 5; i++) {
            vm.expectRevert("Refund was claimed");
            vm.prank(buyerWallets[i]);
            mockSale.claimTokens();
        }

        for (uint256 i = 6; i < 11; i++) {
            vm.prank(buyerWallets[i]);
            mockSale.claimTokens();
        }
        assertEq(tokenMockForSale.balanceOf(address(mockSale)), 0, "Still have tokens left");
    }

    function testGetExcessBackOnBiggerEntrance() public {
        for (uint256 i = 1; i < 6; i++) {
            contributeToBuy(buyerWallets[i], 50 ether);
            assertEq(buyerWallets[i].balance, 49 ether, "No excess refund");
        }
    }

    // Test deploying a sale with invalid parameters
    function testDeployInvalidSale() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.softCap = 5 ether; // Invalid: softCap greater than hardCap
        vm.expectRevert("Sale hardcap is lesser than softcap");
        saleFactory.deploySale(invalidSaleParams);
    }

    // Test deploying a sale with a token that doesn't have enough allowance
    function testDeployInsufficientAllowance() public {
        vm.startPrank(owner);
        tokenMockForSale.approve(address(saleFactory), 0);

        // Expect the transaction to revert with any error
        vm.expectRevert();

        saleFactory.deploySale(saleParams);
        vm.stopPrank();
    }

    // Test finalizing a sale and ensure the team share is sent to the creator
    function testFinalizeTeamShare() public {
        _fillTheSale(mockSale);

        uint256 creatorBalanceBefore = address(owner).balance;
        _finalizeSale();

        uint256 expectedTeamShare = (5 ether * saleParams.teamShare) / DIVISOR;
        assertEq(
            address(owner).balance - creatorBalanceBefore, expectedTeamShare, "Team share should be sent to the creator"
        );
    }

    // Test finalizing a sale and ensure the factory fee is sent to the factory contract
    function testFinalizeFactoryFee() public {
        uint256 factoryBalanceBefore = address(saleFactory).balance;
        _fillTheSale(mockSale);
        _finalizeSale();

        uint256 expectedFactoryFee = (5 ether * saleFactory.getETHFee()) / DIVISOR;
        assertEq(
            address(saleFactory).balance - factoryBalanceBefore,
            expectedFactoryFee,
            "Factory fee should be sent to the factory contract"
        );
    }

    // Test finalizing a sale and ensure any excess sale tokens are sent back to the creator
    function testFinalizeExcessSaleTokens() public {
        uint256 excessTokens = 1000 ether;
        vm.startPrank(owner);
        tokenMockForSale.burn(tokenMockForSale.balanceOf(owner));
        tokenMockForSale.mint(excessTokens);
        tokenMockForSale.transfer(address(mockSale), excessTokens);
        assertEq(tokenMockForSale.balanceOf(owner), 0, "we have more than 0");

        _fillTheSale(mockSale);
        // uint256 excessReal = tokenMockForSale.balanceOf(address(mockSale)) - mockSale.getRequiredAllocationOfTokens();
        uint256 creatorBalanceBefore = tokenMockForSale.balanceOf(owner);
        _finalizeSale();

        assertTrue(
            tokenMockForSale.balanceOf(owner) > creatorBalanceBefore,
            "Excess sale tokens should be sent back to the creator"
        );
    }

    // Test force starting a sale and ensure it can only be done by the creator or factory owner
    function testForceStartSalePermissions() public {
        vm.prank(buyerWallets[1]);
        vm.expectRevert("Caller is not sale creator or factory allowed");
        mockSale.forceStartSale();

        _forceStartSale();
        assertTrue(mockSale.saleStarted(), "Sale should be force started by the creator");

        vm.prank(saleFactory.owner());
        mockSale.forceStartSale();
        assertTrue(mockSale.saleStarted(), "Sale should be force started by the factory owner");
    }

    // Test enabling refunds and ensure it can only be done by the creator or factory owner
    function testEnableRefundsPermissions() public {
        vm.prank(buyerWallets[1]);
        vm.expectRevert("Caller is not sale creator or factory allowed");
        mockSale.enableRefunds();

        _enableRefund();
        assertTrue(mockSale.shouldRefund(), "Refunds should be enabled by the creator");

        vm.prank(saleFactory.owner());
        mockSale.enableRefunds();
        assertTrue(mockSale.shouldRefund(), "Refunds should be enabled by factory owner");
    }

    // Test canceling a sale and ensure it can only be done by the creator or factory owner
    function testCancelSalePermissions() public {
        vm.prank(buyerWallets[1]);
        vm.expectRevert("Caller is not sale creator or factory allowed");
        mockSale.cancelSale();

        vm.prank(owner);
        mockSale.cancelSale();
        assertTrue(mockSale.shouldRefund(), "Sale should be canceled by the creator");

        vm.prank(saleFactory.owner());
        mockSale.cancelSale();
        assertTrue(mockSale.shouldRefund(), "Sale should be canceled by the creator");
    }

    // Test recovering tokens and ensure it can only be done by the factory owner
    function testRecoverTokensPermissions() public {
        uint256 excessTokens = 1000 ether;
        mistakeToken.mint(excessTokens);
        // mistakeToken.burn(0.04 ether);
        mistakeToken.transfer(address(mockSale), excessTokens);

        vm.startPrank(buyerWallets[1]);
        vm.expectRevert("Caller is not sale creator or factory allowed");
        mockSale.recoverTokens(address(mistakeToken));
        vm.stopPrank();

        vm.startPrank(owner);

        uint256 prevBal = mistakeToken.balanceOf(owner);
        mockSale.recoverTokens(address(mistakeToken));

        uint256 diff = mistakeToken.balanceOf(owner) - prevBal;
        assertEq(diff, excessTokens, "Tokens should be recovered by the factory owner");
    }

    function testDeployInsufficientTokenBalance() public {
        vm.startPrank(owner);
        tokenMockForSale.burn(tokenMockForSale.balanceOf(owner));

        vm.expectRevert();
        saleFactory.deploySale(saleParams);
        vm.stopPrank();
    }

    function testDeployInvalidRouter() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.router = address(0);

        vm.expectRevert("Sale target router is empty");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployStartTimeInPast() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.startTime = block.timestamp - 1;

        vm.expectRevert("Invalid sale start time");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployInvalidCreator() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.creator = address(0);

        vm.expectRevert("Sale creator is empty");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployInvalidCreatorNotCaller() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.creator = address(1);

        vm.expectRevert("Creator doesnt match the caller");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployInvalidMaxBuy() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.maxBuy = type(uint256).max;

        vm.expectRevert("invalid maxBuy value");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployInvalidFundingToken() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.fundingToken = address(0x123);

        vm.expectRevert("Invalid funding token");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployInvalidPricing() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.salePrice = 0;

        vm.expectRevert("Sale Price is <=0");
        saleFactory.deploySale(invalidSaleParams);

        invalidSaleParams = saleParams;
        invalidSaleParams.listingPrice = 0;

        vm.expectRevert("Listing Price is <=0");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployInvalidToken() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.token = address(0x123);

        vm.expectRevert("Token not set");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testDeployTokenTransfer() public {
        uint256 tokensNeeded = mockSale.getRequiredAllocationOfTokens();
        uint256 initialTokenBalance = 0;

        // Valid case: Sufficient tokens transferred to the sale contract
        vm.startPrank(owner);
        tokenMockForSale.mint(tokensNeeded);
        tokenMockForSale.approve(address(saleFactory), tokensNeeded);
        address payable newSale = saleFactory.deploySale(saleParams);
        vm.stopPrank();

        assertEq(
            tokenMockForSale.balanceOf(newSale),
            initialTokenBalance + tokensNeeded,
            "Sale contract should have received the required tokens"
        );

        // Invalid case: Insufficient tokens transferred to the sale contract
        vm.startPrank(owner);
        tokenMockForSale.burn(tokenMockForSale.balanceOf(owner));
        tokenMockForSale.mint(tokensNeeded - 1 ether);
        tokenMockForSale.approve(address(saleFactory), tokensNeeded);

        vm.expectRevert();
        saleFactory.deploySale(saleParams);
        vm.stopPrank();
    }

    function testRetrieveETH() public {
        vm.deal(address(saleFactory), 1 ether);

        uint256 balanceBefore = address(owner).balance;
        vm.prank(owner);
        saleFactory.retriveETH();

        assertEq(address(owner).balance - balanceBefore, 1 ether, "ETH should be retrieved by the owner");
    }

    // Test setting a new base sale
    function testSetBaseSale() public {
        address newBaseSale = address(new BaseSale());
        vm.prank(owner);
        saleFactory.setBaseSale(newBaseSale);
        assertEq(saleFactory.baseSale(), newBaseSale, "Base sale should be updated");
    }

    // Test setting a new fee
    function testSetNewFee() public {
        uint256 newFee = 300;
        vm.prank(owner);
        saleFactory.setNewFee(newFee);
        assertEq(saleFactory.getETHFee(), newFee, "Fee should be updated");
    }

    // Test setting a new gas price limit
    function testSetGasPriceLimit() public {
        uint256 newGasPriceLimit = 20 gwei;
        vm.prank(owner);
        saleFactory.setGasPriceLimit(newGasPriceLimit);
        assertEq(saleFactory.gasPriceLimit(), newGasPriceLimit, "Gas price limit should be updated");
    }

    // Test toggling the gas limit
    function testToggleLimit() public {
        bool initialLimit = saleFactory.limitGas();
        vm.prank(owner);
        saleFactory.toggleLimit();
        assertEq(saleFactory.limitGas(), !initialLimit, "Gas limit should be toggled");
    }

    // Test checking the transaction price when the gas limit is enabled
    function testCheckTxPriceWithinLimit() public {
        vm.prank(owner);
        saleFactory.setGasPriceLimit(20 gwei);
        vm.prank(owner);
        saleFactory.toggleLimit();

        assertTrue(saleFactory.checkTxPrice(15 gwei), "Transaction price should be within the limit");
        assertFalse(saleFactory.checkTxPrice(25 gwei), "Transaction price should exceed the limit");
    }

    // Test retrieving tokens from the factory contract
    function testRetrieveToken() public {
        uint256 amount = 100 ether;
        mistakeToken.mint(amount);
        mistakeToken.transfer(address(saleFactory), amount);

        uint256 balanceBefore = mistakeToken.balanceOf(owner);
        vm.prank(owner);
        saleFactory.retriveToken(address(mistakeToken));

        assertEq(mistakeToken.balanceOf(owner) - balanceBefore, amount, "Tokens should be retrieved by the owner");
    }

    // Test finalizing a sale and ensure the remaining funding tokens are sent back to the factory
    function testFinalizeRemainingFundingTokens() public {
        for (uint256 i = 0; i < 5; i++) {
            contributeToBuy(buyerWallets[i], 1 ether);
        }

        _finalizeSale();
        uint256 expectedFeeToFactory = (5 ether * 200) / 10000;

        assertEq(
            address(saleFactory).balance, expectedFeeToFactory, "Factory should have gotten fee for sale completion"
        );
    }

    // Test enabling refunds and canceling the sale, then claiming refunds
    function testEnableRefundsAndCancelSale() public {
        for (uint256 i = 0; i < 5; i++) {
            contributeToBuy(buyerWallets[i], 1 ether);
        }

        uint256 tokenBal = tokenMockForSale.balanceOf(owner);
        vm.prank(owner);
        mockSale.cancelSale();
        uint256 diff = tokenMockForSale.balanceOf(owner) - tokenBal;

        uint256 buyer1BalanceBefore = buyerWallets[1].balance;
        uint256 buyer2BalanceBefore = buyerWallets[2].balance;

        vm.prank(buyerWallets[1]);
        mockSale.getRefund();
        vm.prank(buyerWallets[2]);
        mockSale.getRefund();

        assertEq(diff, mockSale.getRequiredAllocationOfTokens(), "Owner didnt get back tokens");
        assertEq(buyerWallets[1].balance - buyer1BalanceBefore, 1 ether, "Buyer 1 should be refunded");
        assertEq(buyerWallets[2].balance - buyer2BalanceBefore, 1 ether, "Buyer 2 should be refunded");
    }

    // Test trying to finalize a sale before reaching the soft cap
    function testFinalizeSaleBeforeSoftCap() public {
        contributeToBuy(buyerWallets[1], 1 ether);

        vm.expectRevert("Raise amount didnt pass softcap");
        _finalizeSale();
    }

    // Inside the BaseSale test contract

    function testbuyTokensWhenSaleNotStarted() public {
        saleParams.startTime += 1000;
        vm.prank(owner);
        address payable mockSaleAddress = saleFactory.deploySale(saleParams);
        mockSale = BaseSale(mockSaleAddress);
        vm.expectRevert("Not started yet");
        contributeToBuy(buyerWallets[0], 1 ether);
    }

    function testbuyTokensWhenRefundsEnabled() public {
        _enableRefund();
        vm.expectRevert("Not started yet");
        contributeToBuy(buyerWallets[0], 1 ether);
    }

    function testGetRefundWhenUnderHardCap() public {
        contributeToBuy(buyerWallets[1], 1 ether);
        vm.prank(buyerWallets[1]);
        //This will not fail as sale raised is under hardcap
        mockSale.getRefund();
    }

    function testClaimTokensWhenRefundsEnabled() public {
        contributeToBuy(buyerWallets[1], 1 ether);
        _enableRefund();
        vm.expectRevert("Refunds enabled");
        vm.prank(buyerWallets[1]);
        mockSale.claimTokens();
    }

    function testClaimTokensWhenSaleNotFinalized() public {
        contributeToBuy(buyerWallets[1], 1 ether);
        vm.expectRevert("Sale not finalized yet");
        vm.prank(buyerWallets[1]);
        mockSale.claimTokens();
    }

    function testFinalizeWhenTotalRaisedLessThanSoftCap() public {
        contributeToBuy(buyerWallets[1], 1 ether);
        vm.expectRevert("Raise amount didnt pass softcap");
        _finalizeSale();
    }

    function testFinalizeWhenSaleAlreadyFinalized() public {
        _forceStartSale();
        _fillTheSale(mockSale);
        _finalizeSale();
        //Try to finalize again but it will revert cause already finalized
        vm.expectRevert("Sale already finalized");
        _finalizeSale();
    }

    function testInvalidContributeValue() public {
        _forceStartSale();
        vm.expectRevert("Invalid value");
        vm.prank(buyerWallets[1]);
        mockSale.contribute{value: 0}(1);
    }

    function testDeployZeroAddressToken() public {
        CommonStructures.SaleConfig memory invalidSaleParams = saleParams;
        invalidSaleParams.token = address(0);

        vm.expectRevert("Token not set");
        saleFactory.deploySale(invalidSaleParams);
    }

    function testRetrieveTokensWithNoBalance() public {
        uint256 initialBalance = mistakeToken.balanceOf(owner);
        vm.prank(owner);
        saleFactory.retriveToken(address(mistakeToken));
        assertEq(mistakeToken.balanceOf(owner), initialBalance, "Token balance should remain unchanged");
    }

    function testDeployValidSale() public {
        vm.startPrank(owner);
        tokenMockForSale.mint(mockSale.getRequiredAllocationOfTokens());
        tokenMockForSale.approve(address(saleFactory), mockSale.getRequiredAllocationOfTokens());
        address payable newSale = saleFactory.deploySale(saleParams);
        vm.stopPrank();

        assertEq(saleFactory.getAllSales().length, 2, "New sale should be added to the salesDeployed array");
        assertEq(
            tokenMockForSale.balanceOf(newSale),
            mockSale.getRequiredAllocationOfTokens(),
            "New sale should have the required token allocation"
        );
    }

    function testDeployWithoutBaseSale() public {
        vm.prank(owner);
        saleFactory.setBaseSale(address(0));

        vm.expectRevert("Base sale contract not set");
        saleFactory.deploySale(saleParams);
    }

    function testRetrieveETHWithNoBalance() public {
        uint256 initialBalance = address(owner).balance;
        vm.prank(owner);
        saleFactory.retriveETH();
        assertEq(address(owner).balance, initialBalance, "ETH balance should remain unchanged");
    }

    function testToggleGasLimitAndCheckTxPrice() public {
        vm.prank(owner);
        saleFactory.toggleLimit();
        assertTrue(saleFactory.limitGas(), "Gas limit should be enabled");

        uint256 txGasPrice = 5 gwei;
        assertTrue(saleFactory.checkTxPrice(txGasPrice), "Transaction price should be allowed when within the limit");

        txGasPrice = 15 gwei;
        assertFalse(
            saleFactory.checkTxPrice(txGasPrice), "Transaction price should not be allowed when exceeding the limit"
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/SaleData.sol";
import "../contracts/SaleFactory.sol";
import "../contracts/mock/BurnableToken.sol";

contract SaleDataTest is Test {
    SaleData public saleData;
    SaleFactory public saleFactory;
    BaseSale public mockSale1;
    BaseSale public mockSale2;
    BurnableToken public tokenMock;

    address public owner;
    address[] public buyerWallets;

    function setUp() public {
        vm.createSelectFork("mainnet", 19456789);

        owner = address(this);
        buyerWallets = new address[](2);
        buyerWallets[0] = address(0x1);
        buyerWallets[1] = address(0x2);

        saleFactory = new SaleFactory();
        saleData = new SaleData(address(saleFactory));
        tokenMock = new BurnableToken("TestToken", "TSX");

        // Deploy mock sales
        CommonStructures.SaleConfig memory saleConfig = CommonStructures.SaleConfig({
            token: address(tokenMock),
            fundingToken: address(0),
            maxBuy: 1 ether,
            softCap: 3 ether,
            hardCap: 5 ether,
            salePrice: 5,
            listingPrice: 2,
            startTime: block.timestamp + 1000,
            lpUnlockTime: 0,
            detailsJSON: "",
            router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            creator: owner,
            teamShare: 0,
            isV3: false
        });

        tokenMock.approve(address(saleFactory), 100000 ether);
        mockSale1 = BaseSale(payable(deploySale(saleConfig)));

        saleConfig.startTime = block.timestamp + 2000;
        mockSale2 = BaseSale(payable(deploySale(saleConfig)));
    }

    function deploySale(CommonStructures.SaleConfig memory saleConfig) internal returns (address) {
        return saleFactory.deploySale(saleConfig);
    }

    function testGetActiveSalesCount() public {
        assertEq(saleData.getActiveSalesCount(), 0);

        vm.warp(block.timestamp + 1500);
        mockSale1.forceStartSale();
        assertEq(saleData.getActiveSalesCount(), 1);

        vm.warp(block.timestamp + 2500);
        mockSale2.forceStartSale();
        assertEq(saleData.getActiveSalesCount(), 2);

        mockSale1.cancelSale();
        assertEq(saleData.getActiveSalesCount(), 1);
    }

    function testGetParticipatedSalesCount() public {
        assertEq(saleData.getParticipatedSalesCount(buyerWallets[0]), 0);

        contributeTokens(mockSale1, buyerWallets[0]);

        assertEq(saleData.getParticipatedSalesCount(buyerWallets[0]), 1);
        assertEq(saleData.getParticipatedSalesCount(buyerWallets[1]), 0);

        contributeTokens(mockSale2, buyerWallets[0]);

        assertEq(saleData.getParticipatedSalesCount(buyerWallets[0]), 2);
        assertEq(saleData.getParticipatedSalesCount(buyerWallets[1]), 0);
    }

    function testGetRefundableSalesCount() public {
        assertEq(saleData.getRefundableSalesCount(), 0);

        contributeTokens(mockSale1, buyerWallets[0]);
        mockSale1.enableRefunds();

        assertEq(saleData.getRefundableSalesCount(), 1);

        contributeTokens(mockSale2, buyerWallets[0]);
        mockSale2.enableRefunds();

        assertEq(saleData.getRefundableSalesCount(), 2);
    }

    function testGetRefundableSales() public {
        contributeTokens(mockSale1, buyerWallets[0]);
        mockSale1.enableRefunds();

        contributeTokens(mockSale2, buyerWallets[0]);
        mockSale2.enableRefunds();

        address[] memory refundableSales = saleData.getRefundableSales();
        assertEq(refundableSales.length, 2);
        assertEq(refundableSales[0], address(mockSale1));
        assertEq(refundableSales[1], address(mockSale2));
    }

    function testGetParticipatedSalesRefundable() public {
        assertEq(saleData.getParticipatedSalesRefundable(buyerWallets[0]), 0);

        contributeTokens(mockSale1, buyerWallets[0]);
        mockSale1.enableRefunds();

        assertEq(saleData.getParticipatedSalesRefundable(buyerWallets[0]), 1);
        assertEq(saleData.getParticipatedSalesRefundable(buyerWallets[1]), 0);

        contributeTokens(mockSale2, buyerWallets[0]);
        mockSale2.enableRefunds();

        assertEq(saleData.getParticipatedSalesRefundable(buyerWallets[0]), 2);
        assertEq(saleData.getParticipatedSalesRefundable(buyerWallets[1]), 0);
    }

    function testGetSalesActive() public {
        address[] memory activeSales = saleData.getSalesActive();
        assertEq(activeSales.length, 0);

        vm.warp(block.timestamp + 1500);
        mockSale1.forceStartSale();
        activeSales = saleData.getSalesActive();
        assertEq(activeSales.length, 1);
        assertEq(activeSales[0], address(mockSale1));

        vm.warp(block.timestamp + 2500);
        mockSale2.forceStartSale();
        activeSales = saleData.getSalesActive();
        assertEq(activeSales.length, 2);
        assertEq(activeSales[0], address(mockSale1));
        assertEq(activeSales[1], address(mockSale2));
    }

    function testGetSalesUserIsIn() public {
        address[] memory salesParticipated = saleData.getSalesUserIsIn(buyerWallets[0]);
        assertEq(salesParticipated.length, 0);

        contributeTokens(mockSale1, buyerWallets[0]);

        salesParticipated = saleData.getSalesUserIsIn(buyerWallets[0]);
        assertEq(salesParticipated.length, 1);
        assertEq(salesParticipated[0], address(mockSale1));

        contributeTokens(mockSale2, buyerWallets[0]);

        salesParticipated = saleData.getSalesUserIsIn(buyerWallets[0]);
        assertEq(salesParticipated.length, 2);
        assertEq(salesParticipated[0], address(mockSale1));
        assertEq(salesParticipated[1], address(mockSale2));
    }

    function testGetSalesRefundableForUser() public {
        address[] memory salesRefundable = saleData.getSalesRefundableForUser(buyerWallets[0]);
        assertEq(salesRefundable.length, 0);

        contributeTokens(mockSale1, buyerWallets[0]);
        mockSale1.enableRefunds();

        salesRefundable = saleData.getSalesRefundableForUser(buyerWallets[0]);
        assertEq(salesRefundable.length, 1);
        assertEq(salesRefundable[0], address(mockSale1));

        contributeTokens(mockSale2, buyerWallets[0]);
        mockSale2.enableRefunds();

        salesRefundable = saleData.getSalesRefundableForUser(buyerWallets[0]);
        assertEq(salesRefundable.length, 2);
        assertEq(salesRefundable[0], address(mockSale1));
        assertEq(salesRefundable[1], address(mockSale2));
    }

    function contributeTokens(BaseSale sale, address buyer) internal {
        // vm.warp(sale.startTime() + 1500);
        sale.forceStartSale();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        (bool succ,) = address(sale).call{value: 1 ether}("");
        require(succ);
    }
}

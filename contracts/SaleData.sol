//SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
import "./interfaces/IBaseSale.sol";
import "./interfaces/ISaleFactory.sol";

contract SaleData {
    ISaleFactory iSaleFactory;

    constructor(address _saleFactory) {
        iSaleFactory = ISaleFactory(_saleFactory);
    }

    //TODO add ownable and allow to change the factory contract address for data
    //TODO use enumerableSet for data retrival and storage instead

    function getActiveSalesCount() public view returns (uint256 count) {
        address[] memory allSales = iSaleFactory.getAllSales();

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (!refSale.isSaleOver() && refSale.saleStarted()) {
                count++;
            }
        }
    }

    function getParticipatedSalesCount(address user) public view returns (uint256 count) {
        address[] memory allSales = iSaleFactory.getAllSales();

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userData(user).contributedAmount > 0) {
                count++;
            }
        }
    }

    function getRefundableSalesCount() public view returns (uint256 count) {
        address[] memory allSales = iSaleFactory.getAllSales();

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.shouldRefundWithBal()) {
                count++;
            }
        }
    }

    function getRefundableSales() public view returns (address[] memory salesRefundable) {
        salesRefundable = new address[](getRefundableSalesCount());
        uint256 count = 0;
        for (uint256 i = 0; i < salesRefundable.length; i++) {
            IBaseSale refSale = IBaseSale(payable(salesRefundable[i]));
            if (refSale.shouldRefundWithBal()) {
                salesRefundable[count] = address(refSale);
                count++;
            }
        }
    }

    function getParticipatedSalesRefundable(address user) public view returns (uint256 count) {
        address[] memory allSales = iSaleFactory.getAllSales();

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userEligibleToClaimRefund(user)) {
                count++;
            }
        }
    }

    function getSalesActive() external view returns (address[] memory activeSales) {
        address[] memory allSales = iSaleFactory.getAllSales();
        uint256 count = 0;
        activeSales = new address[](getActiveSalesCount());
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (!refSale.isSaleOver() && refSale.saleStarted()) {
                activeSales[count] = allSales[i];
                count++;
            }
        }
    }

    function getSalesUserIsIn(address user) external view returns (address[] memory salesParticipated) {
        address[] memory allSales = iSaleFactory.getAllSales();
        uint256 count = 0;
        salesParticipated = new address[](getParticipatedSalesCount(user));
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userData(user).contributedAmount > 0) {
                salesParticipated[count] = allSales[i];
                count++;
            }
        }
    }

    function getSalesRefundableForUser(address user) external view returns (address[] memory salesRefundable) {
        address[] memory allSales = iSaleFactory.getAllSales();
        uint256 count = 0;
        salesRefundable = new address[](getParticipatedSalesRefundable(user));
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userEligibleToClaimRefund(user)) {
                salesRefundable[count] = allSales[i];
                count++;
            }
        }
    }
}

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
        return count;
    }

    function getRefundableSales() public view returns (address[] memory salesRefundable) {
        address[] memory allSales = iSaleFactory.getAllSales();
        uint256 count = getRefundableSalesCount();
        salesRefundable = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.shouldRefundWithBal()) {
                salesRefundable[index] = address(refSale);
                index++;
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
        uint256 count = getActiveSalesCount();
        activeSales = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (!refSale.isSaleOver() && refSale.saleStarted()) {
                activeSales[index] = allSales[i];
                index++;
            }
        }
    }

    function getSalesUserIsIn(address user) external view returns (address[] memory salesParticipated) {
        address[] memory allSales = iSaleFactory.getAllSales();
        uint256 count = getParticipatedSalesCount(user);
        salesParticipated = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userData(user).contributedAmount > 0) {
                salesParticipated[index] = allSales[i];
                index++;
            }
        }
    }

    function getSalesRefundableForUser(address user) external view returns (address[] memory salesRefundable) {
        address[] memory allSales = iSaleFactory.getAllSales();
        uint256 count = getParticipatedSalesRefundable(user);
        salesRefundable = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userEligibleToClaimRefund(user)) {
                salesRefundable[index] = allSales[i];
                index++;
            }
        }
    }
}

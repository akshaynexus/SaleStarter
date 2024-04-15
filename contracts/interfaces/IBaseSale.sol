//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "../libraries/CommonStructures.sol";

interface IBaseSaleWithoutStructures {
    function isETHSale() external view returns (bool);
    function saleStarted() external view returns (bool);
    function isSaleOver() external view returns (bool);
    function scaleToTokenAmount(uint256 input) external view returns (uint256);
    function getFundingDecimals() external view returns (uint256);
    function calculateTokensClaimable(uint256 valueIn) external view returns (uint256);
    function getTokensToAdd(uint256 ethAmount) external view returns (uint256);
    function getRequiredAllocationOfTokens() external view returns (uint256);
    function getAmountToListWith(uint256 baseValue, uint256 factoryFee) external view returns (uint256 FundingBudget);
    function getRemainingContribution() external view returns (uint256);
    function getFundingBalance() external view returns (uint256);
    function shouldRefundWithBal() external view returns (bool);
    function shouldRefund() external view returns (bool);
    function userEligibleToClaimRefund(address user) external view returns (bool);

    function initialize(CommonStructures.SaleConfig calldata saleConfigNew) external;
    function contribute(uint256 _amount) external payable;
    function getRefund() external;
    function claimTokens() external;
    function enableRefunds() external;
    function forceStartSale() external;
    function cancelSale() external;
    function recoverTokens(address _token) external;
    function finalize() external;
}

//Note : Use this interface to interact with a base sale if you need to
interface IBaseSale is IBaseSaleWithoutStructures {
    function saleConfig() external view returns (CommonStructures.SaleConfig memory);
    function saleInfo() external view returns (CommonStructures.SaleInfo memory);
    function userData(address user) external view returns (CommonStructures.UserData memory);
}

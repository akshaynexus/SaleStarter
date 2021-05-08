//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "../libraries/CommonStructures.sol";

interface IBaseSale {
    function saleStarted() external view returns (bool);

    function isSaleOver() external view returns (bool);
    function shouldRefundWithBal() external view returns (bool);
    function userEligibleToClaimRefund(address) external view returns (bool);
    function userData(address)
        external
        view
        returns (CommonStructures.UserData memory);
}

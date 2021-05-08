//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

interface ISaleFactory {
    function owner() external view returns (address);

    function getETHFee() external view returns (uint256);
    function getAllSales() external view returns (address[] memory);
}

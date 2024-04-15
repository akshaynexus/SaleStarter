//SPDX-License-Identifier: MIT
pragma solidity >=0.8.3;

interface IUniswapRouter01 {
    function factory() external pure returns (address);

    function WETH() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IUniswapV2Router02 is IUniswapRouter01 {}

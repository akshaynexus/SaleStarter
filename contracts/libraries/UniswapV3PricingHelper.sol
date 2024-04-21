pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

library UniswapV3PricingHelper {
    uint256 private constant padding = 1000;
    // Constants
    uint256 private constant Q96 = 2 ** 96;

    function _sortTokens(address _tokenA, address _tokenB)
        internal
        pure
        returns (address _sortedTokenA, address _sortedTokenB)
    {
        require(_tokenA != address(0) && _tokenB != address(0), "Token addresses cannot be zero.");

        // Sort the token addresses
        (_sortedTokenA, _sortedTokenB) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }

    function getInitPrice(address _tokenBase, address _tokenSwap, uint256 tokenBaseAmt, uint256 tokenSwapAmt)
        internal
        pure
        returns (address token0, address token1, uint160 initSQRTPrice)
    {
        (token0, token1) = _sortTokens(_tokenBase, _tokenSwap);
        if (token0 != _tokenBase) initSQRTPrice = encodePriceSqrt(tokenSwapAmt, tokenBaseAmt);
        else initSQRTPrice = encodePriceSqrt(tokenBaseAmt, tokenSwapAmt);
    }

    // Encode price square root function
    function encodePriceSqrt(uint256 reserve0, uint256 reserve1) public pure returns (uint160 sqrtPriceX96) {
        require(reserve0 > 0 && reserve1 > 0, "Reserves must be positive");
        uint256 ratio = Math.sqrt(((reserve1 * padding) / reserve0) / padding) * Q96;
        sqrtPriceX96 = uint160(ratio);
    }
}

//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

library CommonStructures {
    /* what to record
    Token address,
    Presale rate per ETH
    Soft Cap and hardcap
    Contribution Limits
    Liquidity %
    Listing price per eth
    Additional info like telegram,website,github
    LockTime for LP tokens,0 for none,which then goes straight to Owner wallet address
    */
    struct SaleConfig {
        address token;
        uint256 maxBuy;
        uint256 softCap;
        uint256 hardCap;
        uint256 salePrice;
        uint256 listingPrice;
        uint256 startTime;
        uint256 lpUnlockTime;
        string detailsJSON;
        address router;
        address creator;
        uint256 teamShare;
    }

    struct UserData {
        uint256 contributedAmount;
        uint256 tokensClaimable;
        bool tokensClaimed;
        bool refundTaken;
    }
}

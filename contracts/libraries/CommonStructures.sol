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
        uint minBuy;
        uint maxBuy;
        uint softCap;
        uint hardCap;
        uint salePrice;
        uint listingPrice;
        uint startTime;
        uint lpUnlockTime;
        string detailsJSON;
        address router;
        address creator;
        uint teamShare;
    }

    struct UserData {
        uint contributedAmount;
        uint tokensClaimable;
        bool tokensClaimed;
        bool refundTaken;
    }
}
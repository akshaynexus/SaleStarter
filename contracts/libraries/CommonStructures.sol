//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

library CommonStructures {

    struct SaleConfig {
        address token;
        address fundingToken;
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

    struct SaleInfo {
        uint256 totalRaised;
        bool saleForceStarted;
        bool refundEnabled;
        bool refundTaken;
        bool initialized;
        bool finalized;
    }

    struct UserData {
        uint256 contributedAmount;
        uint256 tokensClaimable;
        bool tokensClaimed;
        bool refundTaken;
    }
}

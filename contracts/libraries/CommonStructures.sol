//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

library CommonStructures {
    struct SaleConfig {
        //The token being sold
        address token;
        //The token / asset being accepted as contributions,for ETH its address(0)
        address fundingToken;
        //Max buy in wei
        uint256 maxBuy;
        uint256 softCap;
        uint256 hardCap;
        //Sale price in integers,example 1 or 2 tokens per eth
        uint256 salePrice;
        uint256 listingPrice;
        uint256 startTime;
        uint256 lpUnlockTime;
        //This contains the sale data from backend url
        string detailsJSON;
        //The router which we add liq to,set the positionmanager address here incase its a v3 pool
        address router;
        //Maker of the sale
        address creator;
        //Share of eth / tokens that goes to the team
        uint256 teamShare;
        //Set this to true on uniswap v3 sales
        bool isV3;
    }

    struct SaleInfo {
        //Total amount of ETH or tokens raised
        uint256 totalRaised;
        //The amount of tokens to have to fullfill claims
        uint256 totalTokensToKeep;
        //Force started incase start time is wrong
        bool saleForceStarted;
        //Refunds started incase of a issue with sale contract
        bool refundEnabled;
        //Used to check if the baseSale is init
        bool initialized;
        //Returns if the sale was finalized and listed
        bool finalized;
        // Used as a way to display quality checked sales,shows up on the main page if so
        bool qualitychecked;
    }

    struct UserData {
        //total amount of funding amount contributed
        uint256 contributedAmount;
        uint256 tokensClaimable;
        bool tokensClaimed;
        bool refundTaken;
    }
}

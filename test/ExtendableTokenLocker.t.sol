// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/ExtendableTokenLocker.sol";
import "../contracts/mock/BurnableToken.sol";

contract ExtendableTokenLockerTest is Test {
    ExtendableTokenLocker public locker;
    BurnableToken public token;
    BurnableToken public spamToken;
    address public owner;
    address[] public buyerWallets;

    function setUp() public {
        owner = address(this);
        buyerWallets = new address[](2);
        buyerWallets[0] = address(0x1);
        buyerWallets[1] = address(0x2);

        vm.startPrank(owner);
        token = new BurnableToken("TestToken", "TSX");
        spamToken = new BurnableToken("SpamToken", "SPAM");
        uint256 secondsSinceEpoch = block.timestamp;
        locker = new ExtendableTokenLocker(IERC20(token), owner, secondsSinceEpoch + 2000);
        vm.stopPrank();
    }

    function testTransferBeneficiary() public {
        vm.prank(owner);
        locker.transferBeneficiary(buyerWallets[1]);
        assertEq(locker.beneficiary(), buyerWallets[1]);
    }

    function testExtendLock() public {
        vm.prank(owner);
        locker.extendLocktime(1000);
        assertEq(locker.releaseTime(), block.timestamp + 3000);
    }

    function testSweepLockedToken() public {
        vm.expectRevert("Cant sweep config token");
        vm.prank(owner);
        locker.sweep(address(token));
    }

    function testSweepSentToken() public {
        spamToken.transfer(address(locker), 10000);
        vm.prank(owner);
        locker.sweep(address(spamToken));
        assertEq(spamToken.balanceOf(owner), spamToken.totalSupply());
    }

    function testOnlyBeneficiaryCanTransferBeneficiary() public {
        vm.expectRevert("ExtendableTokenLocker: caller is not the beneficiary");
        vm.prank(buyerWallets[0]);
        locker.transferBeneficiary(buyerWallets[1]);
    }

    function testOnlyBeneficiaryCanExtendLocktime() public {
        vm.expectRevert("ExtendableTokenLocker: caller is not the beneficiary");
        vm.prank(buyerWallets[0]);
        locker.extendLocktime(1000);
    }

    function testOnlyBeneficiaryCanSweep() public {
        spamToken.transfer(address(locker), 10000);

        vm.expectRevert("ExtendableTokenLocker: caller is not the beneficiary");
        vm.prank(buyerWallets[0]);
        locker.sweep(address(spamToken));
    }

    function testReleaseBeforeReleaseTime() public {
        token.transfer(address(locker), 10000);

        vm.expectRevert("ExtendableTokenLocker: current time is before release time");
        locker.release();
    }

    function testReleaseAfterReleaseTime() public {
        token.transfer(address(locker), 10000);

        vm.warp(block.timestamp + 2500);
        locker.release();

        assertEq(token.balanceOf(owner), token.totalSupply());
    }

    function testReleaseWithNoTokens() public {
        vm.warp(block.timestamp + 2500);

        vm.expectRevert("ExtendableTokenLocker: no tokens to release");
        locker.release();
    }
}

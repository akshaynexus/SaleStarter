// SPDX-License-Identifier: MIT
//Extended implementation of Tokentimelock
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
contract ExtendableTokenLocker {
    using SafeERC20 for IERC20;

    // ERC20 basic token contract being held
    IERC20 private immutable _token;

    // beneficiary of tokens after they are released
    address private _beneficiary;

    // timestamp when token release is enabled
    uint256 private _releaseTime;

    event BeneficiaryUpdated(address newBeneficiary);
    event LockTimeExtended(uint256 secondsAdded, uint256 newLockTime);

    constructor(
        IERC20 token_,
        address beneficiary_,
        uint256 releaseTime_
    ) {
        // solhint-disable-next-line not-rely-on-time
        require(
            releaseTime_ > block.timestamp,
            "TokenTimelock: release time is before current time"
        );
        _token = token_;
        _beneficiary = beneficiary_;
        _releaseTime = releaseTime_;
    }

    modifier onlyBeneficiary {
        require(msg.sender == _beneficiary);
        _;
    }

    /**
     * @return the token being held.
     */
    function token() public view virtual returns (IERC20) {
        return _token;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view virtual returns (address) {
        return _beneficiary;
    }

    /**
     * @return the time when the tokens are released.
     */
    function releaseTime() public view virtual returns (uint256) {
        return _releaseTime;
    }

    /**
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release() public virtual {
        // solhint-disable-next-line not-rely-on-time
        require(
            block.timestamp >= releaseTime(),
            "TokenTimelock: current time is before release time"
        );

        uint256 amount = token().balanceOf(address(this));
        require(amount > 0, "TokenTimelock: no tokens to release");

        token().safeTransfer(beneficiary(), amount);
    }

    function sweep(address sweeptoken) public onlyBeneficiary {
        require(sweeptoken != address(token()), "Cant sweep config token");
        IERC20 _tokenInternal = IERC20(sweeptoken);
        uint256 amount = _tokenInternal.balanceOf(address(this));
        require(amount > 0, "TokenTimelock: no tokens to release");

        _tokenInternal.safeTransfer(beneficiary(), amount);
    }

    function transferBeneficiary(address newBeneficiary)
        external
        onlyBeneficiary
    {
        _beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(newBeneficiary);
    }

    function extendLocktime(uint256 _seconds) external onlyBeneficiary {
        _releaseTime += _seconds;
        emit LockTimeExtended(_seconds, _releaseTime);
    }
}

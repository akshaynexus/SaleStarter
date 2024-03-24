// SPDX-License-Identifier: MIT
//Extended implementation of Tokentimelock
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
contract ExtendableTokenLocker is IERC721Receiver {
    using SafeERC20 for IERC20;

    // ERC20 basic token contract being held
    IERC20 private immutable _token;

    // beneficiary of tokens after they are released
    address private _beneficiary;

    // timestamp when token release is enabled
    uint256 private _releaseTime;

    event BeneficiaryUpdated(address newBeneficiary);
    event LockTimeExtended(uint256 secondsAdded, uint256 newLockTime);

    bool public isV3;
    uint256 tokenId;

    constructor(address token_, address beneficiary_, uint256 releaseTime_, bool _isV3) {
        // solhint-disable-next-line not-rely-on-time
        require(releaseTime_ > block.timestamp, "ExtendableTokenLocker: release time is before current time");
        _token = IERC20(token_);
        _beneficiary = beneficiary_;
        _releaseTime = releaseTime_;
        isV3 = _isV3;
    }

    modifier onlyBeneficiary() {
        require(msg.sender == _beneficiary, "ExtendableTokenLocker: caller is not the beneficiary");
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

    function setTokenId(uint256 _id) external {
        require(tokenId == 0, "id already set");
        tokenId = _id;
    }

    /**
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release() public virtual {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp >= releaseTime(), "ExtendableTokenLocker: current time is before release time");
        if (!isV3) {
            uint256 amount = token().balanceOf(address(this));
            require(amount > 0, "ExtendableTokenLocker: no tokens to release");

            token().safeTransfer(beneficiary(), amount);
        } else {
            IERC721 tokenNFT = IERC721(address(token()));
            tokenNFT.safeTransferFrom(address(this), beneficiary(), tokenId, new bytes(0));
        }
    }

    function sweep(address sweeptoken) public onlyBeneficiary {
        require(sweeptoken != address(token()), "Cant sweep config token");
        IERC20 _tokenInternal = IERC20(sweeptoken);
        uint256 amount = _tokenInternal.balanceOf(address(this));
        require(amount > 0, "ExtendableTokenLocker: no tokens to sweep");

        _tokenInternal.safeTransfer(beneficiary(), amount);
    }

    function transferBeneficiary(address newBeneficiary) external onlyBeneficiary {
        _beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(newBeneficiary);
    }

    function extendLocktime(uint256 _seconds) external onlyBeneficiary {
        _releaseTime += _seconds;
        emit LockTimeExtended(_seconds, _releaseTime);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view override returns (bytes4) {
        require(isV3, "Dont accept nfts if not v3 Locker");
        return IERC721Receiver.onERC721Received.selector;
    }
}

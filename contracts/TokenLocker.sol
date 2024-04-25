// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenLocker is Ownable(msg.sender) {
    struct Lock {
        address owner;
        address tokenAddress;
        uint256 amount;
        uint256 unlockTime;
        bool isV3;
        uint256 tokenId;
    }

    Lock[] public locks;

    event TokenLocked(
        address indexed owner,
        address indexed tokenAddress,
        uint256 amount,
        uint256 unlockTime,
        bool isV3,
        uint256 tokenId
    );
    event TokenUnlocked(
        address indexed owner, address indexed tokenAddress, uint256 amount, bool isV3, uint256 tokenId
    );
    event LockExtended(uint256 indexed lockIndex, uint256 newUnlockTime);

    function lockTokens(address _tokenAddress, uint256 _amount, uint256 _unlockTime) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(_unlockTime > block.timestamp, "Unlock time must be in the future");

        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);

        locks.push(Lock(msg.sender, _tokenAddress, _amount, _unlockTime, false, 0));
        emit TokenLocked(msg.sender, _tokenAddress, _amount, _unlockTime, false, 0);
    }

    function lockNFT(address _tokenAddress, uint256 _tokenId, uint256 _unlockTime) external {
        require(_unlockTime > block.timestamp, "Unlock time must be in the future");

        IERC721(_tokenAddress).transferFrom(msg.sender, address(this), _tokenId);

        locks.push(Lock(msg.sender, _tokenAddress, 0, _unlockTime, true, _tokenId));
        emit TokenLocked(msg.sender, _tokenAddress, 0, _unlockTime, true, _tokenId);
    }

    function unlockTokens(uint256 _index) external {
        Lock storage lock = locks[_index];
        require(msg.sender == lock.owner, "Only the lock owner can unlock the tokens");
        require(lock.unlockTime <= block.timestamp, "Tokens are not yet unlocked");

        if (lock.isV3) {
            IERC721(lock.tokenAddress).transferFrom(address(this), msg.sender, lock.tokenId);
            emit TokenUnlocked(msg.sender, lock.tokenAddress, 0, true, lock.tokenId);
        } else {
            IERC20(lock.tokenAddress).transfer(msg.sender, lock.amount);
            emit TokenUnlocked(msg.sender, lock.tokenAddress, lock.amount, false, 0);
        }

        _removeLock(_index);
    }

    function extendLockTime(uint256 _index, uint256 _newUnlockTime) external {
        Lock storage lock = locks[_index];
        require(msg.sender == lock.owner, "Only the lock owner can extend the lock time");
        require(lock.unlockTime > block.timestamp, "Lock has already expired");
        require(_newUnlockTime > lock.unlockTime, "New unlock time must be greater than current unlock time");

        lock.unlockTime = _newUnlockTime;
        emit LockExtended(_index, _newUnlockTime);
    }

    function getActiveLocks() external view returns (Lock[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp) {
                count++;
            }
        }

        Lock[] memory activeLocks = new Lock[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp) {
                activeLocks[index] = locks[i];
                index++;
            }
        }

        return activeLocks;
    }

    function getUpcomingUnlocks() external view returns (Lock[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp && locks[i].unlockTime <= block.timestamp + 30 days) {
                count++;
            }
        }

        Lock[] memory upcomingUnlocks = new Lock[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp && locks[i].unlockTime <= block.timestamp + 30 days) {
                upcomingUnlocks[index] = locks[i];
                index++;
            }
        }

        return upcomingUnlocks;
    }

    function getAllLocks() external view returns (Lock[] memory) {
        return locks;
    }

    function _removeLock(uint256 _index) internal {
        locks[_index] = locks[locks.length - 1];
        locks.pop();
    }
}

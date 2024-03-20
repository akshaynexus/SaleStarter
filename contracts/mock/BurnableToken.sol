// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BurnableToken is ERC20Burnable, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        //Mint initial supply for owner
        _mint(msg.sender, 150000 ether);
    }

    /**
     * @notice Allows owner to mint new tokens
     * @param amount the amount of tokens to mint
     */
    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}

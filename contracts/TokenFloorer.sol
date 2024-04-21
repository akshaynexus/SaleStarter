// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// contract TokenFloorer is Ownable, ReentrancyGuard {
//     IERC20 public swapToken;
//     uint256 public minPrice;
//     uint256 public tokenPrice;

//     constructor(address _swapToken, uint256 _minPrice) {
//         swapToken = IERC20(_swapToken);
//         minPrice = _minPrice;
//     }

//     function getEthPerToken() public view returns (uint256) {
//         return tokenPrice;
//     }

//     function setNewPrice() public onlyOwner {
//         uint256 totalSupply = swapToken.totalSupply();
//         uint256 ethInContract = address(this).balance;
//         uint256 newPrice = (ethInContract * 1e18) / (totalSupply / 1e18);

//         if (newPrice < minPrice) {
//             tokenPrice = minPrice;
//         } else {
//             tokenPrice = newPrice;
//         }
//     }

//     function buyTokens() public payable nonReentrant {
//         require(msg.value > 0, "ETH amount must be greater than zero");

//         uint256 tokensToReceive = (msg.value * 1e18) / tokenPrice;
//         require(swapToken.balanceOf(address(this)) >= tokensToReceive, "Insufficient tokens in the contract");

//         swapToken.transfer(msg.sender, tokensToReceive);
//     }

//     function sellTokens(uint256 tokenAmount) public nonReentrant {
//         require(tokenAmount > 0, "Token amount must be greater than zero");

//         uint256 ethToReceive = (tokenAmount * tokenPrice) / 1e18;
//         require(address(this).balance >= ethToReceive, "Insufficient ETH in the contract");

//         swapToken.transferFrom(msg.sender, address(this), tokenAmount);

//         (bool success, ) = msg.sender.call{value: ethToReceive}("");
//         require(success, "ETH transfer failed");
//     }
// }

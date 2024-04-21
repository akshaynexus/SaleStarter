//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./BaseSale.sol";

contract SaleFactory is Ownable(msg.sender) {
    using Address for address payable;
    using Address for address;
    using SafeERC20 for IERC20;

    //Percent of ETH as service fee,scaled by 100,2% = 200
    uint256 fee;
    //Max gas price in gwei
    uint256 public gasPriceLimit;

    //Toggle to limit max gas per contribution tx
    bool public limitGas;

    //Base sale which we minimal proxy clone for a new sale
    address public baseSale;
    address payable public feeReceiver;
    //Internal array to track all sales deployed
    address[] internal salesDeployed;

    //Events for all admin or nonadmin calls
    event CreatedSale(address newSale);
    event ETHRetrived(address receiver);
    event BaseSaleUpdated(address newBase);
    event ServiceFeeUpdated(uint256 newFee);
    event GasPriceLimitUpdated(uint256 newPrice);
    event LimitToggled(bool cur);
    event SentToken(address token, uint256 amount);

    //Used to receive the service fees
    receive() external payable {}

    constructor() {
        //2% of raised ETH
        fee = 200;
        feeReceiver = payable(msg.sender);
        baseSale = address(new BaseSale());
        gasPriceLimit = 10 gwei;
        limitGas = false;
    }

    //implement iscontract since openzeppelin removed it in recent verisons
    function isContract(address target) internal view returns (bool) {
        return target.code.length > 0;
    }

    function checkContract(address _targetT, bool allowZeroAddr) internal view returns (bool) {
        return (allowZeroAddr ? true : _targetT != address(0))
            && (allowZeroAddr ? address(0) == _targetT : isContract(_targetT));
    }

    function _checkSaleConfig(CommonStructures.SaleConfig memory saleConfigNew) internal view {
        require(checkContract(saleConfigNew.token, false), "Token not set");
        require(checkContract(saleConfigNew.fundingToken, true), "Invalid funding token");
        require(saleConfigNew.maxBuy > 0 && saleConfigNew.maxBuy < type(uint256).max,"invalid maxBuy value");
        require(saleConfigNew.hardCap > saleConfigNew.softCap, "Sale hardcap is lesser than softcap");
        require(saleConfigNew.salePrice > 0, "Sale Price is <=0");
        require(saleConfigNew.listingPrice > 0, "Listing Price is <=0");
        require(saleConfigNew.startTime >= block.timestamp, "Invalid sale start time");
        require(saleConfigNew.lpUnlockTime >= 0, "LP unlock time is invalid");
        require(checkContract(saleConfigNew.router, false), "Sale target router is empty");
        require(saleConfigNew.creator != address(0), "Sale creator is empty");
        require(saleConfigNew.creator == msg.sender, "Creator doesnt match the caller");
        require(saleConfigNew.teamShare >= 0, "Invalid teamshare amount");
    }

    function setBaseSale(address _newBaseSale) external onlyOwner {
        baseSale = _newBaseSale;
        emit BaseSaleUpdated(_newBaseSale);
    }

    function setNewFee(uint256 _newFee) external onlyOwner {
        fee = _newFee;
        emit ServiceFeeUpdated(_newFee);
    }

    function setGasPriceLimit(uint256 _newPrice) external onlyOwner {
        gasPriceLimit = _newPrice;
        emit GasPriceLimitUpdated(_newPrice);
    }

    function toggleLimit() external onlyOwner {
        limitGas = !limitGas;
        emit LimitToggled(limitGas);
    }

    //Used by base sale to check gas prices
    function checkTxPrice(uint256 txGasPrice) external view returns (bool) {
        return limitGas ? txGasPrice <= gasPriceLimit : true;
    }

    function deploySale(CommonStructures.SaleConfig memory saleConfigNew) external returns (address payable newSale) {
        require(baseSale != address(0), "Base sale contract not set");
        _checkSaleConfig(saleConfigNew);
        IERC20 targetToken = IERC20(saleConfigNew.token);
        bytes20 addressBytes = bytes20(baseSale);
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(clone_code, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(add(clone_code, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            newSale := create(0, clone_code, 0x37)
        }

        BaseSale(newSale).initialize(saleConfigNew);

        //Now that this is initialized,transfer tokens to sale contract to get sale prepared
        uint256 tokensNeeded = BaseSale(newSale).getRequiredAllocationOfTokens();
        targetToken.safeTransferFrom(msg.sender, newSale, tokensNeeded);
        require(targetToken.balanceOf(newSale) >= tokensNeeded, "Not enough tokens gotten to new sale");

        salesDeployed.push(newSale);
        emit CreatedSale(newSale);
    }

    function getAllSales() public view returns (address[] memory) {
        return salesDeployed;
    }

    function getETHFee() external view returns (uint256) {
        return fee;
    }

    //Get all eth fees from factory
    function retriveETH() external onlyOwner {
        feeReceiver.sendValue(address(this).balance);
        emit ETHRetrived(msg.sender);
    }

    //Used to retrive tokens which are sent here
    function retriveToken(address token) external onlyOwner {
        IERC20 iToken = IERC20(token);
        uint256 amount = iToken.balanceOf(address(this));
        iToken.safeTransfer(msg.sender, amount);
        emit SentToken(token, amount);
    }
}

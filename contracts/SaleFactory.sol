//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BaseSale.sol";

contract SaleFactory is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    uint256 fee;
    address public baseSale;
    address payable public feeReceiver;
    address[] internal salesDeployed;

    event CreatedSale(address newSale);
    event sentToken (address token,uint amount);

    receive() external payable {}

    constructor() {
        //2% of raised ETH
        fee = 200;
        feeReceiver = payable(msg.sender);
    }

    function setBaseSale(address _newBaseSale) external onlyOwner {
        baseSale = _newBaseSale;
    }

    function setNewFee(uint256 _newFee) external onlyOwner {
        fee = _newFee;
    }

    function deploySale(CommonStructures.SaleConfig memory saleConfigNew)
        external
        returns (address payable newSale)
    {
        require(baseSale != address(0), "Base sale contract not set");
        require(saleConfigNew.creator != address(0), "Sale creator is empty");
        require(
            saleConfigNew.hardCap > saleConfigNew.softCap,
            "Sale hardcap is lesser than softcap"
        );
        //TODO investigate why this fails on tests
        // require(saleConfigNew.startTime >= block.timestamp,"Sale start time is before current time");
        require(
            saleConfigNew.router != address(0),
            "Sale target router is empty"
        );
        require(saleConfigNew.creator == msg.sender,"Creator doesnt match the caller");
        IERC20 targetToken = IERC20(saleConfigNew.token);
        // require(saleConfigNew.)
        bytes20 addressBytes = bytes20(baseSale);
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newSale := create(0, clone_code, 0x37)
        }

        BaseSale(newSale).initialize(saleConfigNew);
        //Now that this is initialized,transfer tokens to sale contract to get sale prepared
        uint tokensNeeded = BaseSale(newSale).getRequiredAllocationOfTokens();
        targetToken.safeTransferFrom(msg.sender, newSale, tokensNeeded);
        require(targetToken.balanceOf(newSale) >= tokensNeeded,"Not enough tokens gotten to new sale");
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
    }

    function retriveToken(address token) external onlyOwner {
        IERC20 iToken = IERC20(token);
        uint amount = iToken.balanceOf(address(this));
        iToken.safeTransfer(msg.sender, amount);
        emit sentToken(token, amount);
    }

}

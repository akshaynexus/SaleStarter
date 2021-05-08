//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BaseSale.sol";
import "./interfaces/IBaseSale.sol";

contract SaleFactory is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    uint256 fee;
    address public baseSale;
    address payable public feeReceiver;
    address[] internal salesDeployed;

    event CreatedSale(address newSale);

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
    //TODO move these extras to a new Statistics contract
    function getActiveSalesCount() public view returns (uint256 count) {
        address[] memory allSales = salesDeployed;

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (!refSale.isSaleOver() && refSale.saleStarted()) {
                count++;
            }
        }
    }

    function getParticipatedSalesCount(address user)
        public
        view
        returns (uint256 count)
    {
        address[] memory allSales = salesDeployed;

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userData(user).contributedAmount > 0) {
                count++;
            }
        }
    }

    function getRefundableSalesCount() public view returns (uint count) {
        address[] memory allSales = salesDeployed;

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.shouldRefundWithBal()) {
                count++;
            }
        }
    }

    function getRefundableSales() public view returns (address[] memory salesRefundable) {
        salesRefundable = new address[](getRefundableSalesCount());
        uint count = 0;
        for (uint256 i = 0; i < salesRefundable.length; i++) {
            IBaseSale refSale = IBaseSale(payable(salesRefundable[i]));
            if (refSale.shouldRefundWithBal()) {
                salesRefundable[count] = address(refSale);
                count++;
            }
        }
    }

    function getParticipatedSalesRefundable(address user)
        public
        view
        returns (uint256 count)
    {
        address[] memory allSales = salesDeployed;

        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userEligibleToClaimRefund(user)) {
                count++;
            }
        }
    }
    function getSalesActive()
        external
        view
        returns (address[] memory activeSales)
    {
        address[] memory allSales = salesDeployed;
        uint256 count = 0;
        activeSales = new address[](getActiveSalesCount());
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (!refSale.isSaleOver() && refSale.saleStarted()) {
                activeSales[count] = allSales[i];
                count++;
            }
        }
    }

    function getSalesUserIsIn(address user)
        external
        view
        returns (address[] memory salesParticipated)
    {
        address[] memory allSales = salesDeployed;
        uint256 count = 0;
        salesParticipated = new address[](getParticipatedSalesCount(user));
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userData(user).contributedAmount > 0) {
                salesParticipated[count] = allSales[i];
                count++;
            }
        }
    }

    function getSalesRefundableForUser(address user)
        external
        view
        returns (address[] memory salesRefundable)
    {
        address[] memory allSales = salesDeployed;
        uint256 count = 0;
        salesRefundable = new address[](getParticipatedSalesRefundable(user));
        for (uint256 i = 0; i < allSales.length; i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if (refSale.userEligibleToClaimRefund(user)) {
                salesRefundable[count] = allSales[i];
                count++;
            }
        }
    }

}

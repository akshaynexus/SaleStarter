//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BaseSale.sol";
import "./interfaces/IBaseSale.sol";

contract SaleFactory is Ownable {
    uint fee;
    address public baseSale;
    address[] internal salesDeployed;

    event CreatedSale(address newSale);

    function setBaseSale(address _newBaseSale) external onlyOwner {
        baseSale = _newBaseSale;
    }

    function setNewFee(uint _newFee) external onlyOwner {
        fee = _newFee;
    }

    function deploySale(CommonStructures.SaleConfig memory saleConfigNew) external returns (address payable newSale) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        require(baseSale != address(0),"Base sale contract not set");
        // require(saleConfigNew.)
        bytes20 addressBytes = bytes20(baseSale);

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
        salesDeployed.push(newSale);
        emit CreatedSale(newSale);
    }

    function getAllSales() public view returns (address[] memory) {
        return salesDeployed;
    }

    function getETHFee() external view returns (uint) {
        return fee;
    }

    function getActiveSalesCount() public view returns (uint count) {
        address[] memory allSales = salesDeployed;

        for(uint i =0;i<allSales.length;i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if(!refSale.isSaleOver() && refSale.saleStarted()){
                count++;
            }
        }
    }

    function getParticipatedSalesCount(address user) public view returns (uint count) {
        address[] memory allSales = salesDeployed;

        for(uint i =0;i<allSales.length;i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if(refSale.userData(user).contributedAmount > 0){
                count++;
            }
        }
    }

    function getSalesActive() external view returns (address [] memory activeSales) {
        address[] memory allSales = salesDeployed;
        uint count=0;
        activeSales = new address[](getActiveSalesCount());
        for(uint i =0;i<allSales.length;i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if(!refSale.isSaleOver() && refSale.saleStarted()){
                activeSales[count] = allSales[i];
                count++;
            }
        }
    }

    function getSalesUserIsIn(address user) external view returns (address[] memory salesParticipated) {
        address[] memory allSales = salesDeployed;
        uint count=0;
        salesParticipated = new address[](getParticipatedSalesCount(user));
        for(uint i =0;i<allSales.length;i++) {
            IBaseSale refSale = IBaseSale(payable(allSales[i]));
            if(refSale.userData(user).contributedAmount > 0){
                salesParticipated[count] = allSales[i];
                count++;
            }
        }
    }


}
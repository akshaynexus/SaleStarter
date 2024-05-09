import "./BurnableToken.sol";

interface CallBack {
    function receivedTokens(uint256 tokens) external;
}

contract ReetrantToken is BurnableToken("Reentrant", "RNT") {
    address targetFrom;
    address callbackto;



    function _update(address from, address to, uint256 value) internal virtual override {
        // if (msg.sender == targetFrom) {
        //     CallBack(callbackto).receivedTokens(value);
        //     // require(false,"callbacksendt");
        // }
        super._update(from, to, value);
    }

    function setTarget(address nTarget) external {
        targetFrom = nTarget;
    }

    function setCallbackTo(address nTarget) external {
        callbackto = nTarget;
    }
}

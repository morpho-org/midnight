// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IMidnight, Market} from "../../interfaces/IMidnight.sol";
import {IRepayCallback} from "../../interfaces/ICallbacks.sol";
import {WAD, CALLBACK_SUCCESS} from "../../libraries/ConstantsLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {ERC20Lib} from "../libraries/ERC20Lib.sol";
import {IReceivableToken} from "./interfaces/IReceivableToken.sol";
import {IReceivableTokenReceiver} from "./interfaces/IReceivableTokenReceiver.sol";

/// @dev Repays debt by withdrawing and redeeming the borrower's receivable collateral.
/// @dev Borrowers must authorize this contract on Midnight. Callback data is an ABI-encoded collateral index.
/// @dev Because the token's rate is at most WAD, redeeming the rounded-up collateral yields exactly `units`.
contract ReceivableRepayer is IRepayCallback, IReceivableTokenReceiver {
    using UtilsLib for uint256;

    error NotMidnight();
    error InconsistentLoanToken();
    error UnexpectedToken();
    error ZeroRate();

    address public immutable midnight;
    address internal transient expectedToken;

    constructor(address _midnight) {
        midnight = _midnight;
    }

    function onRepay(bytes32, Market memory market, uint256 units, address onBehalf, bytes memory data)
        external
        returns (bytes32)
    {
        require(msg.sender == midnight, NotMidnight());
        uint256 collateralIndex = abi.decode(data, (uint256));
        IReceivableToken token = IReceivableToken(market.collateralParams[collateralIndex].token);
        require(token.asset() == market.loanToken, InconsistentLoanToken());
        uint256 rate = token.rate();
        require(rate != 0, ZeroRate());
        uint256 amount = units.mulDivUp(WAD, rate);

        expectedToken = address(token);
        IMidnight(midnight).withdrawCollateral(market, collateralIndex, amount, onBehalf, address(this));

        ERC20Lib.safeApprove(market.loanToken, midnight, units);
        return CALLBACK_SUCCESS;
    }

    function onReceivableTokenReceived(address, uint256 amount) external {
        require(expectedToken != address(0) && msg.sender == expectedToken, UnexpectedToken());
        expectedToken = address(0);
        IReceivableToken(msg.sender).redeem(amount, address(this));
    }
}

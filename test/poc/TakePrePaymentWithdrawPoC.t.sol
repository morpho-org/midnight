// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IBuyCallback} from "../../src/interfaces/ICallbacks.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, LLTV_0, LIQUIDATION_CURSOR_LOW} from "../../src/libraries/ConstantsLib.sol";
import {MAX_TICK} from "../../src/libraries/TickLib.sol";
import {ERC20} from "../erc20s/ERC20.sol";
import {BaseTest} from "../BaseTest.sol";

contract WithdrawFreshCreditCallback is IBuyCallback {
    IMidnight internal immutable midnight;
    address internal immutable ratifier;

    constructor(IMidnight _midnight, address _ratifier) {
        midnight = _midnight;
        ratifier = _ratifier;
        midnight.setIsAuthorized(ratifier, true, address(this));
    }

    function onBuy(
        bytes32,
        Market memory market,
        uint256 buyerAssets,
        uint256 units,
        uint256,
        address buyer,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == address(midnight), "not midnight");
        require(buyer == address(this), "wrong buyer");

        midnight.withdraw(market, units, address(this), address(this));
        ERC20(market.loanToken).approve(address(midnight), buyerAssets);

        return CALLBACK_SUCCESS;
    }
}

/// @title PoC: buyer callback can withdraw freshly-created credit before payment is collected.
contract TakePrePaymentWithdrawPoC is BaseTest {
    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 365 days;
        market.collateralParams.push(
            CollateralParams({
                token: address(collateralToken1),
                lltv: LLTV_0,
                maxLif: maxLif(LLTV_0, LIQUIDATION_CURSOR_LOW),
                oracle: address(oracle1)
            })
        );
        id = toId(market);
    }

    function testBuyerCallbackWithdrawsFreshCreditBeforePayment() public {
        uint256 units = 100e18;

        collateralize(market, borrower, units * 2);
        setupMarket(market, units);

        vm.prank(borrower);
        midnight.repay(market, units, borrower, address(0), "");

        assertEq(midnight.withdrawable(id), units, "initial withdrawable cash");
        assertEq(midnight.creditOf(id, lender), units, "incumbent lender credit");
        assertEq(loanToken.balanceOf(address(midnight)), units, "cash sits in Midnight");

        WithdrawFreshCreditCallback callback = new WithdrawFreshCreditCallback(IMidnight(address(midnight)), address(dummyRatifier));

        collateralize(market, otherBorrower, units * 2);

        Offer memory buyOffer;
        buyOffer.market = market;
        buyOffer.buy = true;
        buyOffer.maker = address(callback);
        buyOffer.callback = address(callback);
        buyOffer.ratifier = address(dummyRatifier);
        buyOffer.maxUnits = units;
        buyOffer.start = vm.getBlockTimestamp();
        buyOffer.expiry = vm.getBlockTimestamp();
        buyOffer.tick = MAX_TICK;

        uint256 sellerBalanceBefore = loanToken.balanceOf(otherBorrower);
        uint256 callbackBalanceBefore = loanToken.balanceOf(address(callback));
        assertEq(callbackBalanceBefore, 0, "callback starts unfunded");

        vm.prank(otherBorrower);
        midnight.take(buyOffer, hex"", units, otherBorrower, otherBorrower, address(0), hex"");

        assertEq(loanToken.balanceOf(address(callback)), 0, "callback keeps no funds");
        assertEq(loanToken.balanceOf(otherBorrower), sellerBalanceBefore + units, "seller paid from prior cash");
        assertEq(loanToken.balanceOf(address(midnight)), 0, "market cash drained");
        assertEq(midnight.withdrawable(id), 0, "withdrawable drained");
        assertEq(midnight.creditOf(id, lender), units, "incumbent still has credit");
        assertEq(midnight.debtOf(id, otherBorrower), units, "new seller debt remains");
        assertEq(midnight.creditOf(id, address(callback)), 0, "fresh buyer credit withdrawn");
    }
}

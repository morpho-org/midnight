// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Obligation, Collateral, Authorization, Signature} from "../src/interfaces/IMorphoV2.sol";
import {DOMAIN_TYPEHASH, AUTHORIZATION_TYPEHASH} from "../src/libraries/ConstantsLib.sol";

import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract OtherFunctionsTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);
    }

    function testSupplyCollateral(address user, uint256 amount) public {
        vm.assume(user != address(morphoV2));
        address collateralToken = address(new ERC20("collat", "c"));
        deal(collateralToken, address(this), amount);
        ERC20(collateralToken).approve(address(morphoV2), amount);

        // Note: you can supply collaterals that are not in the obligation.
        morphoV2.supplyCollateral(obligation, collateralToken, amount, user);

        assertEq(morphoV2.collateralOf(user, id, collateralToken), amount, "collateral of");
        assertEq(ERC20(collateralToken).balanceOf(address(morphoV2)), amount, "balance of morphoV2");
    }

    function testWithdrawCollateralNotAuthorized(address sender, address user, uint256 amount) public {
        vm.assume(sender != user);
        ERC20 collateralToken = new ERC20("collat", "c");
        deal(address(collateralToken), address(user), amount);

        vm.startPrank(user);
        collateralToken.approve(address(morphoV2), amount);
        morphoV2.supplyCollateral(obligation, address(collateralToken), amount, user);
        vm.stopPrank();

        vm.prank(sender);
        vm.expectRevert("withdrawCollateral not authorized");
        morphoV2.withdrawCollateral(obligation, address(collateralToken), amount, user);
    }

    function testWithdrawCollateralNoBorrow(address user, uint256 supply, uint256 withdraw) public {
        vm.assume(user != address(morphoV2));
        withdraw = bound(withdraw, 0, supply);
        address collateralToken = address(new ERC20("collat", "c"));
        deal(collateralToken, address(this), supply);
        ERC20(collateralToken).approve(address(morphoV2), supply);
        morphoV2.supplyCollateral(obligation, collateralToken, supply, user);

        vm.startPrank(user);
        morphoV2.setAuthorized(address(this), true);
        ERC20(collateralToken).approve(address(morphoV2), withdraw);
        vm.stopPrank();

        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, user);

        assertEq(morphoV2.collateralOf(user, id, collateralToken), supply - withdraw, "collateral of");
        assertEq(ERC20(collateralToken).balanceOf(address(morphoV2)), supply - withdraw, "balance of morphoV2");
        assertEq(ERC20(collateralToken).balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 0, MAX_TEST_AMOUNT);
        additionalCollateral = bound(additionalCollateral, 0, MAX_TEST_AMOUNT);
        address collateralToken = obligation.collaterals[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        morphoV2.supplyCollateral(obligation, collateralToken, additionalCollateral, borrower);
        withdraw = bound(withdraw, 0, additionalCollateral);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, collateralToken);

        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, borrower);

        assertEq(morphoV2.collateralOf(borrower, id, collateralToken), initialCollateral - withdraw, "collateral of");
        assertEq(
            ERC20(collateralToken).balanceOf(address(morphoV2)), initialCollateral - withdraw, "balance of morphoV2"
        );
        assertEq(ERC20(collateralToken).balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        additionalCollateral = bound(additionalCollateral, 0, MAX_TEST_AMOUNT);
        address collateralToken = obligation.collaterals[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        morphoV2.supplyCollateral(obligation, collateralToken, additionalCollateral, borrower);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, collateralToken);
        withdraw = bound(withdraw, additionalCollateral + 1, initialCollateral);

        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, borrower);
    }

    function testRepay(uint256 units, uint256 repaid) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        units = bound(units, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        skip(99);
        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        morphoV2.repay(obligation, repaid, borrower);

        assertEq(morphoV2.debtOf(borrower, id), units - repaid);
        assertEq(morphoV2.withdrawable(id), repaid);
        assertEq(loanToken.balanceOf(address(morphoV2)), repaid);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdrawInconsistentInput(uint256 units, uint256 shares) public {
        vm.assume(units > 0 && shares > 0);
        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.withdraw(obligation, units, shares, lender);
    }

    function testWithdrawNotAuthorized(address sender, uint256 obligationUnits) public {
        vm.assume(sender != lender);

        // Setup
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT);
        testRepay(obligationUnits, obligationUnits);

        // Test
        vm.prank(sender);
        vm.expectRevert("withdraw not authorized");
        morphoV2.withdraw(obligation, obligationUnits, 0, lender);
    }

    function testWithdrawWithObligations(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);

        vm.prank(lender);
        morphoV2.setAuthorized(address(this), true);
        vm.prank(address(this));
        morphoV2.withdraw(obligation, withdraw, 0, lender);

        assertEq(morphoV2.sharesOf(lender, id), units - withdraw, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(morphoV2.totalShares(id), units - withdraw, "totalShares");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawWithShares(uint256 units, uint256 shares) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, units);
        testRepay(units, shares);

        // TODO: sharesPrice != 1
        vm.prank(lender);
        morphoV2.setAuthorized(address(this), true);
        vm.prank(address(this));
        morphoV2.withdraw(obligation, 0, shares, lender);

        assertEq(morphoV2.sharesOf(lender, id), units - shares, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(address(this)), shares, "balance of this");
    }

    function testSetRatified(address sender, address maker, bool newRatified, Offer memory offer) public {
        vm.assume(sender != maker);

        offer.maker = maker;

        vm.expectRevert("ratification not authorized");
        vm.prank(sender);
        morphoV2.setRatified(maker, root(offer), newRatified);

        uint256 snap = vm.snapshotState();

        vm.prank(maker);
        morphoV2.setRatified(maker, root(offer), newRatified);
        assertEq(morphoV2.ratified(maker, root(offer)), newRatified);

        vm.revertToStateAndDelete(snap);

        vm.prank(maker);
        morphoV2.setAuthorized(sender, true);
        vm.prank(sender);
        morphoV2.setRatified(maker, root(offer), newRatified);
        assertEq(morphoV2.ratified(maker, root(offer)), newRatified);
    }

    function testSetAuthorized(address authorizer, address authorizee, bool newAuthorized) public {
        vm.prank(authorizer);
        morphoV2.setAuthorized(authorizee, newAuthorized);

        assertEq(morphoV2.authorized(authorizer, authorizee), newAuthorized);
    }

    function _authorizationDigest(Authorization memory authorization) internal view returns (bytes32) {
        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(morphoV2)));
        return keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
    }

    function testSetAuthorizedWithSigDeadlineOutdated(
        uint256 authorizerPrivateKey,
        uint256 elapsed,
        address authorizee,
        bool isAuthorized,
        uint256 otherPrivateKey,
        uint256 wrongNonce
    ) public {
        authorizerPrivateKey = boundPrivateKey(authorizerPrivateKey);
        otherPrivateKey = boundPrivateKey(otherPrivateKey);
        wrongNonce = bound(wrongNonce, 1, type(uint256).max);
        vm.assume(otherPrivateKey != authorizerPrivateKey);
        elapsed = bound(elapsed, 0, 365 days);
        address authorizer = vm.addr(authorizerPrivateKey);

        Authorization memory authorization = Authorization({
            authorizer: authorizer,
            authorizee: authorizee,
            isAuthorized: isAuthorized,
            nonce: 0,
            deadline: vm.getBlockTimestamp() - 1
        });

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(authorizerPrivateKey, _authorizationDigest(authorization));

        skip(elapsed);

        vm.expectRevert("expired");
        morphoV2.setAuthorizedWithSig(authorization, sig);

        authorization.deadline = vm.getBlockTimestamp() + 1;

        sig.v = 1; // make ecrecover return 0
        vm.expectRevert("invalid signature");
        morphoV2.setAuthorizedWithSig(authorization, sig);

        (sig.v, sig.r, sig.s) = vm.sign(otherPrivateKey, _authorizationDigest(authorization));

        vm.expectRevert("invalid signature");
        morphoV2.setAuthorizedWithSig(authorization, sig);

        authorization.nonce = wrongNonce;
        vm.expectRevert("invalid nonce");
        morphoV2.setAuthorizedWithSig(authorization, sig);

        authorization.nonce = 0;
        (sig.v, sig.r, sig.s) = vm.sign(authorizerPrivateKey, _authorizationDigest(authorization));
        morphoV2.setAuthorizedWithSig(authorization, sig);
        assertEq(morphoV2.authorized(authorizer, authorizee), isAuthorized);
        assertEq(morphoV2.authorizationNonce(authorizer), 1);

        vm.expectRevert("invalid nonce");
        morphoV2.setAuthorizedWithSig(authorization, sig);
    }

    function testConsume(address user, bytes32 group, uint256 amount) public {
        vm.prank(user);
        morphoV2.consume(group, amount);
        assertEq(morphoV2.consumed(user, group), amount, "consumed");
    }

    function testShuffleNonce(address user) public {
        vm.prank(user);
        morphoV2.shuffleNonce();
        assertEq(morphoV2.nonce(user), keccak256(abi.encode(0, blockhash(block.number - 1))), "nonce");
    }
}

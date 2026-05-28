// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {
    IEcrecoverAuthorizer,
    Authorization,
    Signature,
    EIP712_DOMAIN_TYPEHASH,
    AUTHORIZATION_TYPEHASH
} from "../src/periphery/interfaces/IEcrecoverAuthorizer.sol";
import {BaseTest} from "./BaseTest.sol";

bytes constant AUTHORIZATION_TYPE =
    "Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)";
bytes constant EIP712_DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)";

contract EcrecoverAuthorizerTest is BaseTest {
    function testAuthorizationTypeHash() public pure {
        assertEq(AUTHORIZATION_TYPEHASH, keccak256(AUTHORIZATION_TYPE));
    }

    function testEip712DomainTypeHash() public pure {
        assertEq(EIP712_DOMAIN_TYPEHASH, keccak256(EIP712_DOMAIN_TYPE));
    }

    function makeAuthorization(address authorizer, address authorized, bool isAuth)
        internal
        view
        returns (Authorization memory)
    {
        return Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuth,
            nonce: ecrecoverAuthorizer.nonce(authorizer),
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }

    function signAuthorization(Authorization memory authorization, address _signer)
        internal
        view
        returns (Signature memory)
    {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ecrecoverAuthorizer)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[_signer], digest);
        return Signature({v: v, r: r, s: s});
    }

    function testEcrecoverAuthorizer() public {
        vm.prank(borrower);
        midnight.setIsAuthorized(address(ecrecoverAuthorizer), true, borrower);
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        Signature memory sig = signAuthorization(auth, borrower);

        ecrecoverAuthorizer.setIsAuthorized(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), true);
        assertEq(ecrecoverAuthorizer.nonce(borrower), 1);

        auth = makeAuthorization(borrower, lender, false);
        sig = signAuthorization(auth, borrower);

        ecrecoverAuthorizer.setIsAuthorized(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), false);
        assertEq(ecrecoverAuthorizer.nonce(borrower), 2);
    }

    function testEcrecoverAuthorizerPermissionless() public {
        vm.prank(borrower);
        midnight.setIsAuthorized(address(ecrecoverAuthorizer), true, borrower);
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        Signature memory sig = signAuthorization(auth, borrower);

        // Anyone can submit — no caller auth needed
        vm.prank(otherLender);
        ecrecoverAuthorizer.setIsAuthorized(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), true);
        assertEq(ecrecoverAuthorizer.nonce(borrower), 1);
    }

    function testEcrecoverAuthorizerInvalidSignature() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        Signature memory sig = signAuthorization(auth, lender); // wrong signer

        vm.expectRevert(IEcrecoverAuthorizer.Unauthorized.selector);
        ecrecoverAuthorizer.setIsAuthorized(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), false);
        assertEq(ecrecoverAuthorizer.nonce(borrower), 0);
    }

    function testEcrecoverAuthorizerExpired() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        auth.deadline = vm.getBlockTimestamp() - 1;
        Signature memory sig = signAuthorization(auth, borrower);

        vm.expectRevert(IEcrecoverAuthorizer.Expired.selector);
        ecrecoverAuthorizer.setIsAuthorized(auth, sig);
    }

    function testEcrecoverAuthorizerInvalidNonce() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        auth.nonce = 999; // wrong nonce
        Signature memory sig = signAuthorization(auth, borrower);

        vm.expectRevert(IEcrecoverAuthorizer.InvalidNonce.selector);
        ecrecoverAuthorizer.setIsAuthorized(auth, sig);
    }

    function testEcrecoverAuthorizerNonce(uint8 n) public {
        vm.prank(borrower);
        midnight.setIsAuthorized(address(ecrecoverAuthorizer), true, borrower);
        n = uint8(bound(n, 1, 32));

        for (uint8 i = 0; i < n; i++) {
            bool isAuth = i % 2 == 0;
            Authorization memory auth = makeAuthorization(borrower, lender, isAuth);
            Signature memory sig = signAuthorization(auth, borrower);

            ecrecoverAuthorizer.setIsAuthorized(auth, sig);

            assertEq(ecrecoverAuthorizer.nonce(borrower), i + 1);
            assertEq(midnight.isAuthorized(borrower, lender), isAuth);
        }
    }
}

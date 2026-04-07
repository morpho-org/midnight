// SPDX-License-Identifier: GPL-2.0-or-later

// Signature verification is verified in tests.

using Midnight as midnight;

methods {
    function nonce(address) external returns (uint256) envfree;
    function MIDNIGHT() external returns (address) envfree;
    function midnight.isAuthorized(address, address) external returns (bool) envfree;
}

/// EcrecoverAuthorizer increments nonce on success and does not change other nonces.
rule effects(env e, EcrecoverAuthorizer.Authorization authorization, EcrecoverAuthorizer.Signature signature, address other) {
    require other != authorization.authorizer;
    uint256 nonceBefore = nonce(authorization.authorizer);
    uint256 otherNonceBefore = nonce(other);

    setIsAuthorized(e, authorization, signature);

    assert nonce(authorization.authorizer) == nonceBefore + 1;
    assert nonce(other) == otherNonceBefore;
}

/// Expired deadline, wrong nonce, and nonce reused cause revert.
rule requiredConditions(env e1, env e2, EcrecoverAuthorizer.Authorization authorization, EcrecoverAuthorizer.Signature signature, EcrecoverAuthorizer.Authorization otherAuthorization, EcrecoverAuthorizer.Signature otherSignature) {
    require authorization.authorizer == otherAuthorization.authorizer;
    uint256 nonceBefore = nonce(authorization.authorizer);

    setIsAuthorized(e1, authorization, signature);

    assert e1.block.timestamp <= authorization.deadline;
    assert authorization.nonce == nonceBefore;

    setIsAuthorized(e2, otherAuthorization, otherSignature);

    assert otherAuthorization.nonce != nonceBefore;
}

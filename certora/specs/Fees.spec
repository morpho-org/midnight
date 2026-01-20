// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function getObligationTradingFee(bytes32 id, uint256 index) external returns (uint256) envfree;
    function getDefaultTradingFee(address loanToken, uint256 index) external returns (uint256) envfree;
}

rule setGetObligationTradingFee(env e, bytes32 id, uint256 index, uint256 newTradingFee) {
    setObligationTradingFee(e, id, index, newTradingFee);

    assert getObligationTradingFee(id, index) == newTradingFee;
}

rule setGetDefaultTradingFee(env e, address loanToken, uint256 index, uint256 newTradingFee) {
    setDefaultTradingFee(e, loanToken, index, newTradingFee);

    assert getDefaultTradingFee(loanToken, index) == newTradingFee;
}

rule setGetOtherObligationTradingFees(env e, bytes32 id, uint256 index, uint256 newTradingFee) {
    bytes32 id2;
    uint256 index2;
    uint256 tradingFee2 = getObligationTradingFee(id2, index2);

    setObligationTradingFee(e, id, index, newTradingFee);

    assert id2 != id || index2 != index => getObligationTradingFee(id2, index2) == tradingFee2;
}

rule setGetOtherDefaultTradingFees(env e, address loanToken, uint256 index, uint256 newTradingFee) {
    address loanToken2;
    uint256 index2;
    uint256 tradingFee2 = getDefaultTradingFee(loanToken2, index2);

    setDefaultTradingFee(e, loanToken, index, newTradingFee);

    assert loanToken2 != loanToken || index2 != index => getDefaultTradingFee(loanToken2, index2) == tradingFee2;
}

// SPDX-License-Identifier: BUSL-1.1
//
//   dowsersRun OneForAll dowsers/oneforall/UpdatePositionViewMarket.sol UpdatePositionViewMarket
//
// updatePositionView keeps its real signature. The body keeps the one read of
// the market, UtilsLib.min(block.timestamp, market.maturity). The caller builds
// that argument with a memory struct literal.
//
pragma solidity 0.8.34;

struct Market {
    uint256 maturity;
}

contract UpdatePositionViewMarket {
    function updatePositionView(Market memory market, bytes32 id, address user) public view returns (uint256) {
        return block.timestamp < market.maturity ? block.timestamp : market.maturity;
    }

    function verify(uint256 maturity, bytes32 id, address user) external view returns (uint256 accrualEnd) {
        accrualEnd = updatePositionView(Market({maturity: maturity}), id, user);
        assert(accrualEnd <= maturity);
    }
}

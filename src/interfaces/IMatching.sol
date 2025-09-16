import "./ITerms.sol";

interface IMatching {
    function check(Term memory term, uint256 assets, uint256 bonds, Make memory make) external;
}

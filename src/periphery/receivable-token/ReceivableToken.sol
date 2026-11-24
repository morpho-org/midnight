// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {WAD, ORACLE_PRICE_SCALE, CALLBACK_SUCCESS} from "../../libraries/ConstantsLib.sol";
import {Market} from "../../interfaces/IMidnight.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {ERC20Lib} from "../libraries/ERC20Lib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {MerkleProofLib} from "./libraries/MerkleProofLib.sol";
import {IReceivableToken} from "./interfaces/IReceivableToken.sol";

/// @dev Claims on the receipts paid to this contract, meant to be used as collateral on Midnight.
///
/// RECEIPTS
/// @dev Receipts are paid in the asset directly to this contract, by plain transfers. Each token is redeemable for
/// `rate` units of the asset as long as the contract holds them.
///
/// REPORTS
/// @dev The owner publishes reports identified by a `rootId`: Merkle roots of `(account, reported)` leaves, where
/// `reported` is the cumulative amount of tokens that `account` may mint under the report. The owner allocates the
/// receipts expected by the token between accounts this way. Reports should be monotone: a new receivable increases
/// `reported`, a receipt does not decrease it.
/// @dev Under a report, an account can have minted at most `reported`. Receipts in excess of the outstanding tokens
/// are extracted the same way: by minting within one's allowance and redeeming.
///
/// RATE
/// @dev The owner sets `rate`, the assets each token redeems for, to the expected recovery over the total reported
/// amount, minted or not, so receipts beyond the outstanding tokens are still extracted by minting and redeeming.
/// For example, with 100 reported, 60 minted and 50 received, a rate of 0.5 lets the holders' 60 redeem for 30 and
/// the minter mint the remaining 40 and redeem for 20. Computing the rate over the outstanding tokens only would let
/// the holders take the cash due to the unminted capacity.
/// @dev A markdown makes the Midnight positions using the token as collateral oracle liquidatable and realizes the
/// uncovered debt as bad debt shared by the market's lenders. Redemptions before the owner updates the rate are first
/// come, first served, like oracle lag before a liquidation.
///
/// HOLDERS
/// @dev Whitelisted accounts are Midnight, this contract, plus every account that has submitted a valid proof under
/// any report, by calling `mint`, possibly with amount 0. The owner can whitelist a non-minter, such as a liquidator
/// or a buyer that wants to keep tokens, by including a leaf with `reported` = 0 in a report. Whitelisting is
/// permanent: leaving an account out of a later report does not remove it.
/// @dev Only whitelisted accounts can receive tokens. Zero-value transfers to any account succeed, so a liquidation
/// that only realizes bad debt works with any receiver.
/// @dev Midnight, set by the factory, is always whitelisted, so nothing can freeze the tokens supplied as
/// collateral on Midnight.
///
/// LIQUIDATIONS
/// @dev Liquidations stay permissionless through this contract's liquidate callback: a liquidator calls Midnight's
/// liquidate with this contract as `receiver` and `callback`. Midnight transfers the seized tokens here, then calls
/// onLiquidate, which burns them, approves Midnight for the repaid units and settles the difference with the
/// liquidator, who never holds the token.
/// @dev If the seized tokens redeem for less than the repaid units, the liquidator pays the difference, so it must
/// approve the token for the asset. When the token is its own collateral oracle, the difference is at most one unit
/// of the asset from rounding. The liquidation reverts if the contract does not hold enough cash.
/// @dev The callback only works on markets whose loan token is the asset. On other markets, only whitelisted
/// accounts can receive seized tokens.
///
/// USAGE
/// @dev Accounts with an allowance mint tokens and can sell them, or supply them as collateral on any Midnight market
/// that lists them and sell debt against them. The debt is repaid either by the borrower, typically with a repay
/// callback that withdraws and redeems the collateral once the receipts are in, or by a liquidator after maturity.
/// @dev If the receipts fall short, the owner marks the rate down: positions using the token as collateral oracle
/// become liquidatable and the uncovered debt is realized as bad debt shared by the market's lenders.
///
/// TRUST
/// @dev The owner fully determines who may mint how much, and who can hold tokens at all through its reports.
/// Holders trust the owner and the payers of the receivables.
/// @dev The owner sets the rate, so it can force liquidations by marking down or delay recognising losses by not
/// marking down.
contract ReceivableToken is IReceivableToken {
    using UtilsLib for uint256;

    /// STORAGE ///

    address public immutable midnight;
    address public immutable asset;
    uint8 public immutable decimals;

    string public name;
    string public symbol;
    address public owner;
    uint256 public rate;
    mapping(address account => bool) internal _isWhitelisted;
    mapping(bytes32 rootId => bytes32) public roots;
    uint256 public totalSupply;
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    /// @dev Tokens minted by the account under the report.
    mapping(bytes32 rootId => mapping(address account => uint256)) public minted;

    /// CONSTRUCTOR ///

    constructor(address _midnight, address _asset, address _owner, string memory _name, string memory _symbol) {
        midnight = _midnight;
        asset = _asset;
        decimals = IERC20(_asset).decimals();
        owner = _owner;
        rate = WAD;
        name = _name;
        symbol = _symbol;
        emit Constructor(_midnight, _asset, _owner, _name, _symbol, decimals);
    }

    /// OWNER FUNCTIONS ///

    function setOwner(address newOwner) external {
        require(msg.sender == owner, NotOwner());
        owner = newOwner;
        emit SetOwner(newOwner);
    }

    /// @dev Leaves are MerkleProofLib.leaf(account, reported).
    function setRoot(bytes32 rootId, bytes32 newRoot) external {
        require(msg.sender == owner, NotOwner());
        roots[rootId] = newRoot;
        emit SetRoot(rootId, newRoot);
    }

    /// @dev Sets the assets each token redeems for, in WAD. Can go down (markdown) and back up (recovery).
    function setRate(uint256 newRate) external {
        require(msg.sender == owner, NotOwner());
        require(newRate <= WAD, RateTooHigh());
        rate = newRate;
        emit SetRate(newRate);
    }

    /// MINTER FUNCTIONS ///

    /// @dev Mints `amount` tokens to the caller, within its allowance under the report.
    /// @dev `reported` and `proof` must match the report's current root, for the leaf (caller, reported).
    /// @dev Whitelists the caller permanently. Calling `mint` with `amount` = 0 is the way to get whitelisted
    /// without minting.
    function mint(bytes32 rootId, uint256 amount, uint256 reported, bytes32[] memory proof) external {
        bytes32 leaf = MerkleProofLib.leaf(msg.sender, reported);
        require(MerkleProofLib.verify(proof, roots[rootId], leaf), InvalidProof());
        uint256 newMinted = minted[rootId][msg.sender] + amount;
        require(newMinted <= reported, ExceedsReceivables());
        minted[rootId][msg.sender] = newMinted;

        if (!_isWhitelisted[msg.sender]) {
            _isWhitelisted[msg.sender] = true;
            emit Whitelist(msg.sender);
        }

        emit Mint(rootId, msg.sender, amount, reported);

        _credit(msg.sender, amount);
        emit Transfer(address(0), msg.sender, amount);
    }

    /// HOLDER FUNCTIONS ///

    /// @dev Burns `amount` tokens of the caller and sends the corresponding assets to `receiver`.
    function redeem(uint256 amount, address receiver) external returns (uint256 assets) {
        assets = amount.mulDivDown(rate, WAD);
        require(assets <= cash(), InsufficientCash());
        _debit(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
        emit Redeem(msg.sender, receiver, amount, assets);
        SafeTransferLib.safeTransfer(asset, receiver, assets);
    }

    /// LIQUIDATE CALLBACK ///

    /// @dev Called by Midnight in a liquidation with this contract as `receiver` and `callback`. Burns the seized
    /// tokens, approves Midnight for `repaidUnits` and settles the difference with the liquidator (`caller`).
    function onLiquidate(
        address caller,
        bytes32 id,
        Market memory market,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        address receiver,
        bytes memory,
        uint256
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(receiver == address(this), InvalidLiquidation());
        require(market.collateralParams[collateralIndex].token == address(this), InvalidLiquidation());
        require(market.loanToken == asset, InvalidLiquidation());

        uint256 assets = seizedAssets.mulDivDown(rate, WAD);
        require(assets <= cash(), InsufficientCash());
        _debit(address(this), seizedAssets);
        emit Transfer(address(this), address(0), seizedAssets);
        emit RedeemSeized(caller, id, borrower, seizedAssets, assets, repaidUnits);

        ERC20Lib.safeApprove(asset, midnight, repaidUnits);
        if (assets >= repaidUnits) SafeTransferLib.safeTransfer(asset, caller, assets - repaidUnits);
        else SafeTransferLib.safeTransferFrom(asset, caller, address(this), repaidUnits - assets);
        return CALLBACK_SUCCESS;
    }

    /// VIEW FUNCTIONS ///

    /// @dev Midnight and this contract are always whitelisted; other accounts once they have proven a leaf in a report.
    function isWhitelisted(address account) public view returns (bool) {
        return account == midnight || account == address(this) || _isWhitelisted[account];
    }

    /// @dev Receipts held by the contract.
    function cash() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @dev The price of one token in `asset`, scaled by 1e36, so the token can be its own collateral oracle on
    /// Midnight markets whose loan token is `asset` (token and asset have the same decimals). Not valid for other
    /// loan tokens.
    function price() external view returns (uint256) {
        return rate.mulDivDown(ORACLE_PRICE_SCALE, WAD);
    }

    /// ERC20 ///

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, InsufficientAllowance());
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowed - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    /// HELPERS ///

    function _transfer(address from, address to, uint256 amount) internal {
        _debit(from, amount);
        _credit(to, amount);
        emit Transfer(from, to, amount);
    }

    /// @dev Only whitelisted accounts receive tokens; zero-value credits are no-ops for any account.
    function _credit(address to, uint256 amount) internal {
        require(amount == 0 || isWhitelisted(to), NotWhitelisted());
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function _debit(address from, uint256 amount) internal {
        uint256 balance = balanceOf[from];
        require(balance >= amount, InsufficientBalance());
        balanceOf[from] = balance - amount;
        totalSupply -= amount;
    }
}

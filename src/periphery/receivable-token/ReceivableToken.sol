// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {CALLBACK_SUCCESS} from "../../libraries/ConstantsLib.sol";
import {Market} from "../../interfaces/IMidnight.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {ERC20Lib} from "../libraries/ERC20Lib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {MerkleProofLib} from "./libraries/MerkleProofLib.sol";
import {IReceivableToken} from "./interfaces/IReceivableToken.sol";

/// @dev Claims on the receipts paid to this contract, meant to be used as collateral on Midnight.
///
/// RECEIPTS
/// @dev Receipts are paid in the asset directly to this contract, by plain transfers. Each token is redeemable for one
/// unit of the asset as long as the contract holds it.
///
/// REPORT
/// @dev The immutable `root` commits to a report of `(account, reported)` leaves, where `reported` is the cumulative
/// amount that `account` may mint. Excess receipts can only be extracted by minting within the fixed allowances
/// and redeeming.
///
/// REDEMPTIONS
/// @dev Tokens redeem one for one, first come, first served: if the receipts fall short, the last holders to redeem
/// bear the shortfall.
///
/// HOLDERS
/// @dev Whitelisted accounts are Midnight, this contract, accounts the owner whitelists via `whitelist`, and
/// accounts that successfully call `mint`. Whitelisting is permanent.
/// @dev Only whitelisted accounts can receive tokens. Zero-value transfers to any account succeed, so a liquidation
/// that only realizes bad debt works with any receiver.
/// @dev Midnight, set by the factory, is always whitelisted, so nothing can freeze the tokens supplied as
/// collateral on Midnight.
///
/// LIQUIDATIONS
/// @dev Liquidations stay permissionless through this contract's liquidate callback: a liquidator calls Midnight's
/// liquidate with this contract as `receiver` and `callback`. Midnight transfers the seized tokens here, then calls
/// onLiquidate, which burns them, approves Midnight for the repaid units and sends the rest of the seized amount, in
/// assets, to the liquidator, who never holds the token.
/// @dev With an oracle valuing the token at one unit of the asset, the repaid units never exceed the seized tokens,
/// since the liquidation incentive is at least 1, so the liquidator needs no capital. The liquidation reverts if the
/// repaid units exceed the seized tokens, which can happen once the oracle values the token above one unit of the
/// asset, or if the contract does not hold enough cash.
/// @dev The callback only works on markets whose loan token is the asset. On other markets, only whitelisted
/// accounts can receive seized tokens.
///
/// USAGE
/// @dev Accounts with an allowance mint tokens and can sell them, or supply them as collateral on any Midnight market
/// that lists them and sell debt against them. The debt is repaid either by the borrower, typically with a repay
/// callback that withdraws and redeems the collateral once the receipts are in, or by a liquidator after maturity.
///
/// TRUST
/// @dev The report fixes who may mint and how much. Holders trust `signer` (verified by the factory over all
/// deployment parameters), `owner` to whitelist other holders, and the payers to pay the receivables.
/// @dev `midnight` and `signer` are only guaranteed for tokens registered in `ReceivableTokenFactory.isReceivableToken`.
contract ReceivableToken is IReceivableToken {
    /// STORAGE ///
    address public immutable midnight;
    address public immutable asset;
    address public immutable owner;
    address public immutable signer;
    uint8 public immutable decimals;
    bytes32 public immutable root;

    string public name;
    string public symbol;
    mapping(address account => bool) internal _isWhitelisted;
    uint256 public totalSupply;
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    /// @dev Total tokens minted by the account.
    mapping(address account => uint256) public minted;

    /// CONSTRUCTOR ///

    constructor(
        address _midnight,
        address _asset,
        address _owner,
        address _signer,
        string memory _name,
        string memory _symbol,
        bytes32 _root
    ) {
        midnight = _midnight;
        asset = _asset;
        owner = _owner;
        signer = _signer;
        decimals = IERC20(_asset).decimals();
        root = _root;
        name = _name;
        symbol = _symbol;
        emit Constructor(_midnight, _asset, _owner, _signer, _name, _symbol, decimals, _root);
    }

    /// OWNER FUNCTION ///

    /// @dev Whitelists `account` permanently.
    function whitelist(address account) external {
        require(msg.sender == owner, NotOwner());
        _whitelist(account);
    }

    /// MINTER FUNCTIONS ///

    /// @dev Mints `amount` tokens to the caller, within its allowance under the report, and whitelists the caller.
    /// @dev `reported` and `proof` must match `root` for the leaf (caller, reported).
    function mint(uint256 amount, uint256 reported, bytes32[] memory proof) external {
        bytes32 leaf = MerkleProofLib.leaf(msg.sender, reported);
        require(MerkleProofLib.verify(proof, root, leaf), InvalidProof());
        uint256 newMinted = minted[msg.sender] + amount;
        require(newMinted <= reported, ExceedsReceivables());
        minted[msg.sender] = newMinted;

        _whitelist(msg.sender);
        emit Mint(msg.sender, amount, reported);

        _credit(msg.sender, amount);
        emit Transfer(address(0), msg.sender, amount);
    }

    /// HOLDER FUNCTIONS ///

    /// @dev Burns `amount` tokens of the caller and sends `amount` assets to `receiver`.
    function redeem(uint256 amount, address receiver) external {
        require(amount <= cash(), InsufficientCash());
        _debit(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
        emit Redeem(msg.sender, receiver, amount);
        SafeTransferLib.safeTransfer(asset, receiver, amount);
    }

    /// LIQUIDATE CALLBACK ///

    /// @dev Called by Midnight in a liquidation with this contract as `receiver` and `callback`. Burns the seized
    /// tokens, approves Midnight for `repaidUnits` and sends the remaining assets to the liquidator (`caller`).
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

        require(seizedAssets <= cash(), InsufficientCash());
        _debit(address(this), seizedAssets);
        emit Transfer(address(this), address(0), seizedAssets);
        emit RedeemSeized(caller, id, borrower, seizedAssets, repaidUnits);

        ERC20Lib.safeApprove(asset, midnight, repaidUnits);
        SafeTransferLib.safeTransfer(asset, caller, seizedAssets - repaidUnits);
        return CALLBACK_SUCCESS;
    }

    /// VIEW FUNCTIONS ///

    /// @dev Midnight and this contract are always whitelisted; other accounts are whitelisted via `whitelist` or `mint`.
    function isWhitelisted(address account) public view returns (bool) {
        return account == midnight || account == address(this) || _isWhitelisted[account];
    }

    /// @dev Receipts held by the contract.
    function cash() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
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

    function _whitelist(address account) internal {
        if (!_isWhitelisted[account]) {
            _isWhitelisted[account] = true;
            emit Whitelist(account);
        }
    }

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

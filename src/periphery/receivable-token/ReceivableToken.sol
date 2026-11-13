// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {WAD, ORACLE_PRICE_SCALE} from "../../libraries/ConstantsLib.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {MerkleProofLib} from "./libraries/MerkleProofLib.sol";
import {IReceivableToken} from "./interfaces/IReceivableToken.sol";
import {IReceivableTokenReceiver} from "./interfaces/IReceivableTokenReceiver.sol";

/// @dev Claims on the receipts paid to this contract, meant to be used as collateral on Midnight.
///
/// RECEIPTS
/// @dev Receipts are paid in the asset directly to this contract, by plain transfers. Each token is redeemable for
/// `rate` units of the asset as long as the contract holds them.
///
/// REPORTS
/// @dev The owner publishes reports identified by a `rootId`: Merkle roots of `(key, reported)` leaves, each a chunk of
/// `reported` tokens that the holder of `key` may mint once, to any account. The owner allocates the receipts expected
/// by the token in chunks this way.
/// @dev Receipts in excess of the outstanding tokens are extracted the same way: by minting unminted chunks and
/// redeeming.
/// @dev Each `key` is a one-time ERC-5564 scheme 1 stealth address that the owner derives from the user's spending and
/// viewing public keys (see the README), so outsiders cannot link chunks or brute-force their amounts as long as every
/// leaf uses a fresh key.
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
/// @dev Whitelisted accounts are Midnight plus every account that has been minted to under any report, possibly with
/// amount 0. The owner can whitelist a non-minter, such as a liquidator or a buyer that wants to keep tokens, by
/// including a leaf keyed by that account with `reported` = 0 in a report. Whitelisting is permanent: leaving an
/// account out of a later report does not remove it.
/// @dev Only whitelisted accounts hold tokens across transactions. Any other account can still receive tokens, but
/// only transiently: the token credits them in transient storage, calls onReceivableTokenReceived on the receiver,
/// and reverts if the receiver still holds tokens when the call returns. The receiver must redeem them or transfer
/// them to a whitelisted account in that call. In particular, accounts without code cannot receive tokens unless
/// whitelisted.
/// @dev This keeps liquidations on Midnight permissionless: Midnight transfers the seized tokens to the liquidator
/// before pulling the repayment, so the liquidator redeems them in onReceivableTokenReceived and pays with the
/// proceeds.
/// @dev Midnight, set by the factory, is always whitelisted, so nothing can freeze the tokens supplied as
/// collateral on Midnight.
///
/// USAGE
/// @dev This contract does not interact with Midnight. Chunk key holders mint tokens and can sell them, or
/// supply them as collateral on any Midnight market that lists them and sell debt against them. The debt is repaid
/// either by the borrower, typically with a repay callback that withdraws and redeems the collateral once the receipts
/// are in, or by a liquidator after maturity who then redeems the seized tokens.
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

    /// @dev Transient storage slot of the balances of non-whitelisted accounts. Solidity does not support transient
    /// mappings yet.
    uint256 internal constant TRANSIENT_BALANCE_SLOT = uint256(keccak256("morpho.receivable.transientBalance"));

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
    /// @dev Tokens held by whitelisted accounts.
    uint256 internal _totalSupply;
    /// @dev Balances of whitelisted accounts.
    mapping(address account => uint256) internal _balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    /// @dev Whether the leaf has been minted.
    mapping(bytes32 leaf => bool) public minted;
    /// @dev Tokens transiently held by non-whitelisted accounts in this transaction.
    uint256 public transient transientSupply;

    /// CONSTRUCTOR ///

    constructor(address _midnight, address _asset, address _owner, string memory _name, string memory _symbol) {
        midnight = _midnight;
        asset = _asset;
        decimals = IERC20(_asset).decimals();
        owner = _owner;
        rate = WAD;
        name = _name;
        symbol = _symbol;
        emit Constructor(_midnight, _asset, _owner, _name, _symbol);
    }

    /// OWNER FUNCTIONS ///

    function setOwner(address newOwner) external {
        require(msg.sender == owner, NotOwner());
        owner = newOwner;
        emit SetOwner(newOwner);
    }

    /// @dev Leaves are MerkleProofLib.leaf(key, reported).
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

    /// @dev Mints the leaf's `reported` tokens to `to`, once per leaf.
    /// @dev `key`, `reported` and `proof` must match the report's current root. The caller must be `key`, or relay
    /// `key`'s signature over `keccak256(abi.encode(block.chainid, address(this), leaf, to))`, signed with the EIP-191
    /// `personal_sign` prefix.
    /// @dev Whitelists `to` permanently. Minting a leaf with `reported` = 0 is the way to get whitelisted without
    /// minting.
    function mint(
        bytes32 rootId,
        address key,
        uint256 reported,
        bytes32[] memory proof,
        address to,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 leaf = MerkleProofLib.leaf(key, reported);
        require(MerkleProofLib.verify(proof, roots[rootId], leaf), InvalidProof());
        require(!minted[leaf], AlreadyMinted());
        minted[leaf] = true;
        // forge-lint: disable-next-item(ecrecover) malleability is ok because each leaf can only be minted once.
        require(
            msg.sender == key
                || (key != address(0)
                    && ecrecover(
                        keccak256(
                            abi.encodePacked(
                                "\x19Ethereum Signed Message:\n32",
                                keccak256(abi.encode(block.chainid, address(this), leaf, to))
                            )
                        ),
                        v,
                        r,
                        s
                    ) == key),
            InvalidSignature()
        );

        if (!_isWhitelisted[to]) {
            _isWhitelisted[to] = true;
            emit Whitelist(to);
        }

        emit Mint(rootId, leaf, to, reported);
        _credit(to, reported);
        emit Transfer(address(0), to, reported);
    }

    /// HOLDER FUNCTIONS ///

    /// @dev Burns `amount` tokens of the caller and sends the corresponding assets to `receiver`.
    /// @dev Works for transient holders too, which is how liquidators cash out seized tokens.
    function redeem(uint256 amount, address receiver) external returns (uint256 assets) {
        assets = amount.mulDivDown(rate, WAD);
        require(assets <= cash(), InsufficientCash());
        _debit(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
        emit Redeem(msg.sender, receiver, amount, assets);
        SafeTransferLib.safeTransfer(asset, receiver, assets);
    }

    /// VIEW FUNCTIONS ///

    /// @dev Tokens held by whitelisted accounts, plus those transiently held in this transaction.
    function totalSupply() public view returns (uint256) {
        return _totalSupply + transientSupply;
    }

    /// @dev Midnight is always whitelisted; other accounts once they have been minted to under a report.
    function isWhitelisted(address account) public view returns (bool) {
        return account == midnight || _isWhitelisted[account];
    }

    /// @dev Whitelisted accounts hold tokens across transactions, other accounts only within one.
    function balanceOf(address account) public view returns (uint256) {
        return isWhitelisted(account) ? _balanceOf[account] : _tload(_transientBalanceSlot(account));
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
        }
        _transfer(from, to, amount);
        return true;
    }

    /// HELPERS ///

    function _transfer(address from, address to, uint256 amount) internal {
        _debit(from, amount);
        _credit(to, amount);
        emit Transfer(from, to, amount);
        if (!isWhitelisted(to)) {
            IReceivableTokenReceiver(to).onReceivableTokenReceived(from, amount);
            require(_tload(_transientBalanceSlot(to)) == 0, TransientBalanceNotSettled());
        }
    }

    function _credit(address to, uint256 amount) internal {
        if (isWhitelisted(to)) {
            _balanceOf[to] += amount;
            _totalSupply += amount;
        } else {
            uint256 slot = _transientBalanceSlot(to);
            _tstore(slot, _tload(slot) + amount);
            transientSupply += amount;
        }
    }

    function _debit(address from, uint256 amount) internal {
        if (isWhitelisted(from)) {
            uint256 balance = _balanceOf[from];
            require(balance >= amount, InsufficientBalance());
            _balanceOf[from] = balance - amount;
            _totalSupply -= amount;
        } else {
            uint256 slot = _transientBalanceSlot(from);
            uint256 balance = _tload(slot);
            require(balance >= amount, InsufficientBalance());
            _tstore(slot, balance - amount);
            transientSupply -= amount;
        }
    }

    function _transientBalanceSlot(address account) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(account, TRANSIENT_BALANCE_SLOT)));
    }

    function _tload(uint256 slot) internal view returns (uint256 value) {
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }

    function _tstore(uint256 slot, uint256 value) internal {
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }
}

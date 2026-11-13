// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK, TickLib} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";
import {IERC20} from "../src/periphery/receivable-token/interfaces/IERC20.sol";
import {MerkleProofLib} from "../src/periphery/receivable-token/libraries/MerkleProofLib.sol";
import {IReceivableTokenFactory} from "../src/periphery/receivable-token/interfaces/IReceivableTokenFactory.sol";
import {IReceivableToken} from "../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {FlashLiquidator} from "./helpers/FlashLiquidator.sol";
import {MintReceiver} from "./helpers/MintReceiver.sol";
import {TransientReceiver} from "./helpers/TransientReceiver.sol";

contract ReceivableTokenTest is BaseTest {
    using UtilsLib for uint256;

    uint256 internal constant REPORTED = 1_000e18;
    uint256 internal constant OTHER_REPORTED = 500e18;
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 internal constant STEALTH_SPENDING_PRIVATE_KEY = 12345;
    uint256 internal constant STEALTH_VIEWING_PRIVATE_KEY = 54321;
    uint256 internal constant STEALTH_EPHEMERAL_PRIVATE_KEY = 67890;
    // forgefmt: disable-start
    /*
// Pinned: @scopelift/stealth-address-sdk@1.0.0-beta.5 (viem@2.57.7), @noble/secp256k1@2.3.0, @noble/hashes@1.8.0, @openzeppelin/merkle-tree@1.0.8.
// Run with: bun vectors.ts (bun 1.4.2; the SDK's dist uses extensionless ESM imports that Node cannot resolve).
import { computeStealthKey, generateStealthAddress, VALID_SCHEME_ID } from "@scopelift/stealth-address-sdk";
import * as secp from "@noble/secp256k1";
import { keccak_256 } from "@noble/hashes/sha3";
import { bytesToHex } from "@noble/hashes/utils";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

const hex32 = (value: bigint) => `0x${value.toString(16).padStart(64, "0")}`;
const hex = (bytes: Uint8Array) => `0x${bytesToHex(bytes)}`;
const assertEq = (a: string, b: string, what: string) => {
  if (a.toLowerCase() !== b.toLowerCase()) throw new Error(`${what} mismatch: ${a} != ${b}`);
};

const n = secp.CURVE.n;
const k = 12345n; // spending private key
const v = 54321n; // viewing private key
const r = 67890n; // ephemeral private key
const K = secp.getPublicKey(secp.etc.hexToBytes(hex32(k).slice(2)), true);
const V = secp.getPublicKey(secp.etc.hexToBytes(hex32(v).slice(2)), true);
const stealthMetaAddressURI = `st:eth:${hex(K)}${bytesToHex(V)}`;

// SDK: owner side, then user side.
const sdk = generateStealthAddress({
  stealthMetaAddressURI,
  schemeId: VALID_SCHEME_ID.SCHEME_ID_1,
  ephemeralPrivateKey: secp.etc.hexToBytes(hex32(r).slice(2)),
});
const sdkPrivateKey = computeStealthKey({
  ephemeralPublicKey: sdk.ephemeralPublicKey as `0x${string}`,
  schemeId: VALID_SCHEME_ID.SCHEME_ID_1,
  spendingPrivateKey: hex32(k) as `0x${string}`,
  viewingPrivateKey: hex32(v) as `0x${string}`,
});

// Plain @noble/secp256k1 cross-check.
const R = secp.ProjectivePoint.BASE.multiply(r);
const S = secp.ProjectivePoint.fromHex(V).multiply(r);
const userS = R.multiply(v);
if (!S.equals(userS)) throw new Error("shared secret mismatch");
const SCompressed = S.toRawBytes(true);
const sh = BigInt(hex(keccak_256(SCompressed)));
const viewTag = `0x${hex32(sh).slice(2, 4)}`;
const P = secp.ProjectivePoint.fromHex(K).add(secp.ProjectivePoint.BASE.multiply(sh)).toRawBytes(false);
const key = `0x${bytesToHex(keccak_256(P.slice(1)).slice(-20))}`;
const privateKey = (k + sh) % n;
if (secp.ProjectivePoint.BASE.multiply(privateKey).equals(secp.ProjectivePoint.fromHex(P)) === false) {
  throw new Error("stealth private key mismatch");
}

assertEq(sdk.ephemeralPublicKey, hex(R.toRawBytes(true)), "R");
assertEq(sdk.viewTag, viewTag, "view tag");
assertEq(sdk.stealthAddress, key, "stealth address");
assertEq(sdkPrivateKey, hex32(privateKey), "stealth private key");

const tree = StandardMerkleTree.of(
  [
    [sdk.stealthAddress, "25000000000000000000"],
    ["0x000000000000000000000000000000000000dEaD", "1000000000000000000"],
  ],
  ["address", "uint256"],
);

const Su = S.toRawBytes(false);
const Ru = R.toRawBytes(false);
const Ku = secp.ProjectivePoint.fromHex(K).toRawBytes(false);
const Vu = secp.ProjectivePoint.fromHex(V).toRawBytes(false);
console.log(`k=${hex32(k)}`);
console.log(`v=${hex32(v)}`);
console.log(`r=${hex32(r)}`);
console.log(`stealthMetaAddressURI=${stealthMetaAddressURI}`);
console.log(`Kx=${hex(Ku.slice(1, 33))}`);
console.log(`Ky=${hex(Ku.slice(33))}`);
console.log(`Vx=${hex(Vu.slice(1, 33))}`);
console.log(`Vy=${hex(Vu.slice(33))}`);
console.log(`R=${sdk.ephemeralPublicKey}`);
console.log(`Rx=${hex(Ru.slice(1, 33))}`);
console.log(`Ry=${hex(Ru.slice(33))}`);
console.log(`S=${hex(SCompressed)}`);
console.log(`Sx=${hex(Su.slice(1, 33))}`);
console.log(`Sy=${hex(Su.slice(33))}`);
console.log(`sh=${hex32(sh)}`);
console.log(`viewTag=${sdk.viewTag}`);
console.log(`key=${sdk.stealthAddress}`);
console.log(`privateKey=${sdkPrivateKey}`);
console.log(`root=${tree.root}`);
console.log(`leaf=${tree.leafHash([sdk.stealthAddress, "25000000000000000000"])}`);
console.log(`proof=${JSON.stringify(tree.getProof(0))}`);
*/
    // forgefmt: disable-end
    uint256 internal constant STEALTH_SPENDING_PUBLIC_X =
        0xf01d6b9018ab421dd410404cb869072065522bf85734008f105cf385a023a80f;
    uint256 internal constant STEALTH_SPENDING_PUBLIC_Y =
        0x0eba29d0f0c5408ed681984dc525982abefccd9f7ff01dd26da4999cf3f6a295;
    uint256 internal constant STEALTH_VIEWING_PUBLIC_X =
        0x9d2d304374a5d5571d7d8c39db99c8eed149767dcaf70be1a356a08376caa34f;
    uint256 internal constant STEALTH_VIEWING_PUBLIC_Y =
        0x10d960983fcdeb4ca99b41c2e846add30c0dec73de02aae3aef5f609a70309a5;
    uint256 internal constant STEALTH_EPHEMERAL_PUBLIC_X =
        0x54006a630e70fca8d45a696d7dba3a1cb7d81cc830cfce3be0f634373aac3f0a;
    uint256 internal constant STEALTH_EPHEMERAL_PUBLIC_Y =
        0x32d92c4207b931604884cfdd494c2af6ee5995f490180cbd8fa39200fefe47f8;
    bytes internal constant STEALTH_EPHEMERAL_PUBLIC_KEY =
        hex"0254006a630e70fca8d45a696d7dba3a1cb7d81cc830cfce3be0f634373aac3f0a";
    uint256 internal constant STEALTH_SHARED_X = 0xb4c7a6f5a20bf666e43af95e5fa04d19bb44dd0d1c9ff0e80817b3e323b4e108;
    uint256 internal constant STEALTH_SHARED_Y = 0xfd8d371ad2e3b47d58219b030fb22649347a0ece9ed68655d8323e533fd6591b;
    bytes internal constant STEALTH_SHARED_COMPRESSED =
        hex"03b4c7a6f5a20bf666e43af95e5fa04d19bb44dd0d1c9ff0e80817b3e323b4e108";
    uint256 internal constant STEALTH_HASHED_SHARED_SECRET =
        0x218ead9be1508f0f1819fe12f4de8764f4db34785a8c1703d4d6f4653bc8c175;
    uint8 internal constant STEALTH_VIEW_TAG = 0x21;
    address internal constant STEALTH_KEY = 0xfd028863fCC80F7bb86b41D964cF3B41dc84B9B0;
    uint256 internal constant STEALTH_PRIVATE_KEY = 0x218ead9be1508f0f1819fe12f4de8764f4db34785a8c1703d4d6f4653bc8f1ae;
    bytes32 internal constant STEALTH_TREE_ROOT = 0xbcbde96952bf9a97b689f52d9ba06713555359c7ae63745b799086a6d002513b;
    bytes32 internal constant STEALTH_TREE_PROOF = 0x2cd783aaad1a726bc1eb1972b42e56bbacddc40ccb34415a6f2b4ee19c89c8f3;
    uint256 internal constant TICK = MAX_TICK - 400; // price < 1, multiple of the default tick spacing.
    bytes32 internal constant ROOT_A = keccak256("A");
    bytes32 internal constant ROOT_C = keccak256("C");
    bytes32 internal constant ROOT_D = keccak256("D");

    address internal payer = makeAddr("payer");
    address internal stranger = makeAddr("stranger");
    address internal minter;
    address internal otherMinter;

    IReceivableTokenFactory internal factory;
    IReceivableToken internal token;
    IReceivableToken internal otherToken;
    bytes32[] internal proof; // minter on token.
    bytes32[] internal otherProof; // otherMinter on otherToken (single leaf, empty proof).
    bytes32[] internal lenderProof; // lender on token.
    bytes32[] internal emptyProof; // proof of a leaf in a single-leaf root.
    uint256 internal maturity;
    uint256 internal rootNonce;

    function setUp() public override {
        super.setUp();
        minter = borrower;
        otherMinter = otherBorrower;
        midnight.enableLltv(WAD);
        maturity = vm.getBlockTimestamp() + 30 days;

        // Midnight's test tokens do not expose decimals.
        vm.mockCall(address(loanToken), abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(18)));
        factory = IReceivableTokenFactory(deployCode("ReceivableTokenFactory.sol", abi.encode(address(midnight))));
        token = IReceivableToken(
            factory.createReceivableToken(minter, address(loanToken), "Receivable A", "rA", bytes32(0))
        );
        otherToken = IReceivableToken(
            factory.createReceivableToken(otherMinter, address(loanToken), "Receivable B", "rB", bytes32(0))
        );
        // Roots are per token: the token's has two leaves, the other token's a single one.
        bytes32 leaf = MerkleProofLib.leaf(minter, REPORTED);
        bytes32 lenderLeaf = MerkleProofLib.leaf(lender, 0);
        bytes32 otherLeaf = MerkleProofLib.leaf(otherMinter, OTHER_REPORTED);
        bytes32 root = _hashPair(leaf, lenderLeaf);
        proof.push(lenderLeaf);
        lenderProof.push(leaf);
        vm.startPrank(minter);
        token.setRoot(ROOT_A, root);
        token.setRoot(ROOT_C, MerkleProofLib.leaf(liquidator, 0));
        vm.stopPrank();
        vm.prank(otherMinter);
        otherToken.setRoot(ROOT_A, otherLeaf);

        // The lender is whitelisted by proving its leaf, without minting.
        vm.prank(lender);
        token.mint(ROOT_A, lender, 0, lenderProof, lender, 0, bytes32(0), bytes32(0));

        deal(address(loanToken), lender, 10 * REPORTED);
        deal(address(loanToken), payer, 10 * REPORTED);
        vm.prank(minter);
        token.approve(address(midnight), type(uint256).max);
    }

    /// HELPERS ///

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _setSingleLeafRoot(IReceivableToken _token, bytes32 rootId, address key, uint256 amount)
        internal
        returns (bytes32 leaf)
    {
        leaf = MerkleProofLib.leaf(key, amount);
        vm.prank(_token.owner());
        _token.setRoot(rootId, leaf);
    }

    function _mintDigest(IReceivableToken _token, bytes32 leaf, address to) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32", keccak256(abi.encode(block.chainid, address(_token), leaf, to))
            )
        );
    }

    function _market() internal view returns (Market memory) {
        return _market(WAD);
    }

    function _market(uint256 lltv) internal view returns (Market memory) {
        return _market(lltv, address(oracle1));
    }

    function _market(uint256 lltv, address oracle) internal view returns (Market memory) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(token), lltv: lltv, liquidationCursor: LIQUIDATION_CURSOR, oracle: oracle
        });
        return Market({
            chainId: block.chainid,
            midnight: address(midnight),
            loanToken: address(loanToken),
            collateralParams: collateralParams,
            maturity: maturity,
            rcfThreshold: 1e18,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
    }

    function _buyOffer(Market memory market) internal view returns (Offer memory offer) {
        offer.market = market;
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = type(uint128).max;
        offer.continuousFeeCap = type(uint256).max;
        offer.ratifier = address(dummyRatifier);
        offer.expiry = type(uint256).max;
        offer.tick = TICK;
    }

    function _mint(uint256 amount) internal returns (bytes32 leaf) {
        bytes32 rootId = keccak256(abi.encode(address(token), rootNonce++));
        address key = address(uint160(uint256(keccak256(abi.encode(rootId)))));
        leaf = MerkleProofLib.leaf(key, amount);
        vm.prank(minter);
        token.setRoot(rootId, leaf);
        vm.prank(key);
        token.mint(rootId, key, amount, emptyProof, minter, 0, bytes32(0), bytes32(0));
    }

    /// @dev The liquidator is whitelisted by proving its `reported` = 0 leaf under ROOT_C, without minting.
    function _whitelistLiquidator() internal {
        vm.prank(liquidator);
        token.mint(ROOT_C, liquidator, 0, emptyProof, liquidator, 0, bytes32(0), bytes32(0));
    }

    /// @dev Receipts are plain transfers to the token.
    function _pay(IReceivableToken _token, uint256 amount) internal {
        vm.prank(payer);
        SafeTransferLib.safeTransfer(address(loanToken), address(_token), amount);
    }

    /// FACTORY ///

    function testCreateReceivableToken() public {
        assertTrue(factory.isReceivableToken(address(token)), "isReceivableToken");
        assertEq(token.name(), "Receivable A", "name");
        assertEq(token.symbol(), "rA", "symbol");
        assertTrue(address(token) != address(otherToken), "distinct");
        assertEq(token.owner(), minter, "owner");
        assertFalse(token.isWhitelisted(minter), "minter whitelisted on first mint");
        assertTrue(token.isWhitelisted(lender), "lender whitelisted by proving its leaf");
        assertFalse(otherToken.isWhitelisted(minter), "whitelist is per token");
        assertEq(token.asset(), address(loanToken), "asset");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(token.rate(), WAD, "rate");
        assertEq(factory.midnight(), address(midnight), "factory midnight");
        assertEq(token.midnight(), address(midnight), "token midnight");
        assertTrue(otherToken.isWhitelisted(address(midnight)), "midnight whitelisted");

        // Same owner, asset and salt with the same parameters: already deployed. Another salt: another token.
        vm.expectRevert();
        factory.createReceivableToken(minter, address(loanToken), "Receivable A", "rA", bytes32(0));
        address created =
            factory.createReceivableToken(stranger, address(loanToken), "Fresh", "FRS", bytes32(uint256(1)));
        assertTrue(factory.isReceivableToken(created), "fresh registered");
        assertEq(IReceivableToken(created).owner(), stranger, "fresh owner");
    }

    function testDecimalsMirrorAsset() public {
        vm.mockCall(address(loanToken), abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(6)));
        IReceivableToken created = IReceivableToken(
            factory.createReceivableToken(minter, address(loanToken), "Six", "SIX", bytes32(uint256(6)))
        );
        assertEq(created.decimals(), 6, "decimals");

        vm.clearMockedCalls();
        vm.expectRevert();
        factory.createReceivableToken(minter, address(loanToken), "None", "NONE", bytes32(uint256(7)));
    }

    function testSetters() public {
        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.setOwner(address(this));
        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.setRoot(ROOT_A, bytes32(0));
        vm.prank(minter);
        token.setOwner(address(this));
        token.setRoot(ROOT_A, bytes32(uint256(1)));
        assertEq(token.owner(), address(this), "owner");
        assertEq(token.roots(ROOT_A), bytes32(uint256(1)), "root");
    }

    /// RATE ///

    function testSetRate() public {
        assertEq(token.rate(), WAD, "rate at creation");

        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.setRate(WAD / 2);

        vm.startPrank(minter);
        vm.expectRevert(IReceivableToken.RateTooHigh.selector);
        token.setRate(WAD + 1);
        vm.expectEmit(address(token));
        emit IReceivableToken.SetRate(WAD / 2);
        token.setRate(WAD / 2);
        vm.stopPrank();
        assertEq(token.rate(), WAD / 2, "rate");
    }

    function testPrice(uint256 newRate) public {
        newRate = bound(newRate, 0, WAD);
        assertEq(token.price(), 1e36, "price at par");
        vm.prank(minter);
        token.setRate(newRate);
        assertEq(token.price(), newRate * 1e18, "price tracks the rate");
    }

    /// MINT ///

    function testMint(uint256 amount) public {
        amount = bound(amount, 1, REPORTED);
        bytes32 leaf = _mint(amount);
        assertEq(token.balanceOf(minter), amount, "balance");
        assertEq(token.totalSupply(), amount, "supply");
        assertTrue(token.minted(leaf), "minted");
    }

    function testMintOtherMinter() public {
        vm.prank(otherMinter);
        otherToken.mint(ROOT_A, otherMinter, OTHER_REPORTED, otherProof, otherMinter, 0, bytes32(0), bytes32(0));
        assertEq(otherToken.balanceOf(otherMinter), OTHER_REPORTED, "balance");

        // Roots are per token: the minter's proof is not valid on the other token.
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        otherToken.mint(ROOT_A, minter, 1, proof, minter, 0, bytes32(0), bytes32(0));
    }

    function testMintInvalidProof() public {
        vm.startPrank(minter);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, minter, REPORTED + 1, proof, minter, 0, bytes32(0), bytes32(0));
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, minter, REPORTED, lenderProof, minter, 0, bytes32(0), bytes32(0));
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(keccak256("unknown"), minter, REPORTED, proof, minter, 0, bytes32(0), bytes32(0));
        vm.stopPrank();

        // A leaf only works for its own key.
        vm.prank(lender);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, lender, REPORTED, proof, lender, 0, bytes32(0), bytes32(0));

        // An invalid proof does not whitelist the caller.
        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, minter, REPORTED + 1, proof, stranger, 0, bytes32(0), bytes32(0));
        assertFalse(token.isWhitelisted(stranger), "stranger not whitelisted");
    }

    function testStealthDerivationMatches() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 hashedSharedSecret = STEALTH_HASHED_SHARED_SECRET;
        Vm.Wallet memory spending = vm.createWallet(STEALTH_SPENDING_PRIVATE_KEY);
        Vm.Wallet memory viewing = vm.createWallet(STEALTH_VIEWING_PRIVATE_KEY);
        Vm.Wallet memory ephemeral = vm.createWallet(STEALTH_EPHEMERAL_PRIVATE_KEY);
        // The owner computes S = r·V and the user S = v·R.
        Vm.Wallet memory ownerShared =
            vm.createWallet(mulmod(STEALTH_EPHEMERAL_PRIVATE_KEY, STEALTH_VIEWING_PRIVATE_KEY, SECP256K1_N));
        Vm.Wallet memory userShared =
            vm.createWallet(mulmod(STEALTH_VIEWING_PRIVATE_KEY, STEALTH_EPHEMERAL_PRIVATE_KEY, SECP256K1_N));
        bytes memory compressedEphemeral =
            bytes.concat(bytes1(ephemeral.publicKeyY % 2 == 0 ? 0x02 : 0x03), bytes32(ephemeral.publicKeyX));
        bytes memory compressedShared =
            bytes.concat(bytes1(ownerShared.publicKeyY % 2 == 0 ? 0x02 : 0x03), bytes32(ownerShared.publicKeyX));

        assertEq(spending.publicKeyX, STEALTH_SPENDING_PUBLIC_X, "spending public key x");
        assertEq(spending.publicKeyY, STEALTH_SPENDING_PUBLIC_Y, "spending public key y");
        assertEq(viewing.publicKeyX, STEALTH_VIEWING_PUBLIC_X, "viewing public key x");
        assertEq(viewing.publicKeyY, STEALTH_VIEWING_PUBLIC_Y, "viewing public key y");
        assertEq(ephemeral.publicKeyX, STEALTH_EPHEMERAL_PUBLIC_X, "ephemeral public key x");
        assertEq(ephemeral.publicKeyY, STEALTH_EPHEMERAL_PUBLIC_Y, "ephemeral public key y");
        assertEq(compressedEphemeral, STEALTH_EPHEMERAL_PUBLIC_KEY, "compressed ephemeral public key");
        assertEq(ownerShared.publicKeyX, STEALTH_SHARED_X, "shared point x");
        assertEq(ownerShared.publicKeyY, STEALTH_SHARED_Y, "shared point y");
        assertEq(userShared.publicKeyX, STEALTH_SHARED_X, "user shared point x");
        assertEq(userShared.publicKeyY, STEALTH_SHARED_Y, "user shared point y");
        assertEq(compressedShared, STEALTH_SHARED_COMPRESSED, "compressed shared point");
        assertEq(uint256(keccak256(compressedShared)), hashedSharedSecret, "hashed shared secret");
        assertEq(uint8(hashedSharedSecret >> 248), STEALTH_VIEW_TAG, "view tag");
        assertEq(
            addmod(STEALTH_SPENDING_PRIVATE_KEY, hashedSharedSecret, SECP256K1_N), privateKey, "stealth private key"
        );
        assertEq(vm.addr(privateKey), key, "owner and user derive same key");
    }

    function testStealthChunkFromStandardMerkleTree() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 amount = 25e18;
        address to = makeAddr("standard merkle destination");
        bytes32 leaf = MerkleProofLib.leaf(key, amount);
        bytes32[] memory stealthProof = new bytes32[](1);
        stealthProof[0] = STEALTH_TREE_PROOF;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _mintDigest(token, leaf, to));

        vm.prank(minter);
        token.setRoot(ROOT_D, STEALTH_TREE_ROOT);
        vm.prank(stranger);
        token.mint(ROOT_D, key, amount, stealthProof, to, v, r, s);

        assertEq(token.balanceOf(to), amount, "destination balance");
    }

    function testRelayedMintToChosenDestination() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 amount = 25e18;
        bytes32 rootId = ROOT_D;
        bytes32 leaf = _setSingleLeafRoot(token, rootId, key, amount);
        address to = makeAddr("mint destination");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _mintDigest(token, leaf, to));

        vm.prank(stranger);
        token.mint(rootId, key, amount, emptyProof, to, v, r, s);

        assertEq(token.balanceOf(to), amount, "destination balance");
        assertTrue(token.isWhitelisted(to), "destination whitelisted");
        assertTrue(token.minted(leaf), "leaf minted");
    }

    function testDirectMint() public {
        address key = stranger;
        uint256 amount = 7e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, key, amount);

        vm.prank(key);
        token.mint(ROOT_D, key, amount, emptyProof, key, 0, bytes32(0), bytes32(0));

        assertEq(token.balanceOf(key), amount, "key balance");
        assertTrue(token.minted(leaf), "leaf minted");
    }

    function testLeafMintsOnce() public {
        uint256 amount = 1e18;
        _setSingleLeafRoot(token, ROOT_D, minter, amount);

        vm.prank(minter);
        token.mint(ROOT_D, minter, amount, emptyProof, minter, 0, bytes32(0), bytes32(0));
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.AlreadyMinted.selector);
        token.mint(ROOT_D, minter, amount, emptyProof, minter, 0, bytes32(0), bytes32(0));
    }

    function testReplacedRootKeepsLeafMinted() public {
        uint256 amount = 1e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, minter, amount);

        vm.prank(minter);
        token.mint(ROOT_D, minter, amount, emptyProof, minter, 0, bytes32(0), bytes32(0));

        bytes32 otherLeaf = MerkleProofLib.leaf(stranger, 2e18);
        bytes32[] memory replacementProof = new bytes32[](1);
        replacementProof[0] = otherLeaf;

        vm.prank(minter);
        token.setRoot(ROOT_D, _hashPair(leaf, otherLeaf));

        vm.prank(minter);
        vm.expectRevert(IReceivableToken.AlreadyMinted.selector);
        token.mint(ROOT_D, minter, amount, replacementProof, minter, 0, bytes32(0), bytes32(0));
    }

    function testSignatureForDifferentDestinationIsInvalid() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 amount = 1e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, key, amount);
        address signedTo = makeAddr("signed destination");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _mintDigest(token, leaf, signedTo));

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidSignature.selector);
        token.mint(ROOT_D, key, amount, emptyProof, makeAddr("other destination"), v, r, s);
    }

    function testSignatureForOtherChainIsInvalid() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 amount = 1e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, key, amount);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _mintDigest(token, leaf, stranger));
        vm.chainId(block.chainid + 1);

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidSignature.selector);
        token.mint(ROOT_D, key, amount, emptyProof, stranger, v, r, s);
    }

    function testRawHashSignatureIsInvalid() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 amount = 1e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, key, amount);
        address to = makeAddr("raw hash destination");
        bytes32 rawHash = keccak256(abi.encode(block.chainid, address(token), leaf, to));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, rawHash);

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidSignature.selector);
        token.mint(ROOT_D, key, amount, emptyProof, to, v, r, s);
    }

    function testZeroKeyCannotMintWithInvalidSignature() public {
        uint256 amount = 1e18;
        _setSingleLeafRoot(token, ROOT_D, address(0), amount);

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidSignature.selector);
        token.mint(ROOT_D, address(0), amount, emptyProof, stranger, 0, bytes32(0), bytes32(0));
    }

    function testMalleatedSignatureMintsSameLeaf() public {
        address key = STEALTH_KEY;
        uint256 privateKey = STEALTH_PRIVATE_KEY;
        uint256 amount = 1e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, key, amount);
        address to = makeAddr("malleated signature destination");
        bytes32 digest = _mintDigest(token, leaf, to);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes32 highS = bytes32(SECP256K1_N - uint256(s));
        uint8 highV = v == 27 ? uint8(28) : uint8(27);

        vm.prank(stranger);
        token.mint(ROOT_D, key, amount, emptyProof, to, highV, r, highS);
        assertEq(token.balanceOf(to), amount, "malleated signature mints to signed destination");

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.AlreadyMinted.selector);
        token.mint(ROOT_D, key, amount, emptyProof, to, v, r, s);
    }

    function testOwnerCannotSignWithStealthOffsetAlone() public {
        // The owner and the viewing-key holder both know s_h, but neither can mint without the spending key k.
        address key = STEALTH_KEY;
        uint256 hashedSharedSecret = STEALTH_HASHED_SHARED_SECRET;
        uint256 amount = 1e18;
        bytes32 leaf = _setSingleLeafRoot(token, ROOT_D, key, amount);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hashedSharedSecret, _mintDigest(token, leaf, stranger));

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidSignature.selector);
        token.mint(ROOT_D, key, amount, emptyProof, stranger, v, r, s);
    }

    /// EXCESS RECEIPTS ///

    function testExcessReceiptsAreExtractedByMintingAndRedeeming() public {
        _mint(300e18);
        _pay(token, 500e18);

        // The minter takes the 200 of excess by minting another chunk and redeeming.
        _mint(200e18);
        vm.prank(minter);
        token.redeem(200e18, minter);
        assertEq(loanToken.balanceOf(minter), 200e18, "extracted");
        assertEq(token.cash(), 300e18, "cash still backs the outstanding tokens");
        assertEq(token.totalSupply(), 300e18, "supply");

        // Beyond the cash held, minting works but redeeming waits for the receipts.
        _mint(300e18);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InsufficientCash.selector);
        token.redeem(300e18 + 1, minter);
    }

    /// REDEEM ///

    function testRedeemAtFace(uint256 amount) public {
        amount = bound(amount, 1, REPORTED);
        _mint(amount);
        vm.prank(minter);
        token.transfer(lender, amount);
        _pay(token, amount);

        vm.expectEmit(address(token));
        emit IReceivableToken.Transfer(lender, address(0), amount);
        vm.expectEmit(address(token));
        emit IReceivableToken.Redeem(lender, lender, amount, amount);
        vm.prank(lender);
        token.redeem(amount, lender);

        assertEq(loanToken.balanceOf(lender), 10 * REPORTED + amount, "lender cash");
        assertEq(token.totalSupply(), 0, "supply");
        assertEq(token.cash(), 0, "cash");
    }

    function testRedeemAtRate(uint256 amount, uint256 newRate) public {
        amount = bound(amount, 1, REPORTED);
        newRate = bound(newRate, 0, WAD);
        _mint(amount);
        _pay(token, amount);
        vm.prank(minter);
        token.setRate(newRate);

        uint256 assets = amount.mulDivDown(newRate, WAD);
        vm.prank(minter);
        assertEq(token.redeem(amount, minter), assets, "assets returned");
        assertEq(loanToken.balanceOf(minter), assets, "assets paid");
        assertEq(token.balanceOf(minter), 0, "tokens burned");
    }

    function testRateCanGoBackUp() public {
        _mint(100e18);
        _pay(token, 100e18);
        vm.startPrank(minter);
        token.setRate(WAD / 2);
        token.setRate(WAD);
        uint256 assets = token.redeem(100e18, minter);
        vm.stopPrank();
        assertEq(assets, 100e18, "redeemed at the new rate");
    }

    function testRateDistributesRecoveryOverReported() public {
        // Reported 1000, minted 600, received 500: the rate is 0.5.
        _mint(600e18);
        _pay(token, 500e18);
        vm.prank(minter);
        token.setRate(WAD / 2);

        vm.prank(minter);
        assertEq(token.redeem(600e18, minter), 300e18, "holders redeem at the rate");

        // The unminted capacity is still extracted by minting and redeeming.
        _mint(400e18);
        vm.prank(minter);
        assertEq(token.redeem(400e18, minter), 200e18, "unminted capacity redeemed");
        assertEq(token.cash(), 0, "cash");
    }

    function testRedeemRequiresCash() public {
        _mint(100e18);
        _pay(token, 60e18);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InsufficientCash.selector);
        token.redeem(60e18 + 1, minter);
        vm.prank(minter);
        token.redeem(60e18, minter);
        assertEq(loanToken.balanceOf(minter), 60e18, "cash");
    }

    function testRedeemInsufficientBalance() public {
        _mint(1);
        _pay(token, 2);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InsufficientBalance.selector);
        token.redeem(2, minter);
    }

    /// WHITELIST ///

    function testMintWhitelists() public {
        assertFalse(token.isWhitelisted(minter), "not whitelisted");
        vm.prank(minter);
        token.setRoot(ROOT_A, MerkleProofLib.leaf(minter, 0));
        vm.expectEmit(address(token));
        emit IReceivableToken.Whitelist(minter);
        vm.prank(minter);
        token.mint(ROOT_A, minter, 0, emptyProof, minter, 0, bytes32(0), bytes32(0));
        assertTrue(token.isWhitelisted(minter), "whitelisted");

        // A second mint does not emit Whitelist again.
        vm.recordLogs();
        _mint(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IReceivableToken.Whitelist.selector, "no second Whitelist");
        }
    }

    function testWhitelistingIsPermanent() public {
        _mint(1);
        // The owner replaces the root with one that does not contain the lender.
        vm.prank(minter);
        token.setRoot(ROOT_A, MerkleProofLib.leaf(minter, REPORTED));

        assertTrue(token.isWhitelisted(lender), "still whitelisted");
        vm.prank(minter);
        token.transfer(lender, 1);
        assertEq(token.balanceOf(lender), 1, "received");
    }

    function testWhitelistingInHookDoesNotSettle() public {
        _mint(100e18);
        MintReceiver receiver = new MintReceiver();
        vm.prank(minter);
        token.setRoot(ROOT_C, MerkleProofLib.leaf(address(receiver), 0));
        receiver.configure(ROOT_C, 0, emptyProof);

        // Whitelisting itself in the hook does not settle the tokens received before the hook.
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.TransientBalanceNotSettled.selector);
        token.transfer(address(receiver), 100e18);
    }

    function testTransientReceiverSettlesInHook() public {
        _mint(300e18);
        _pay(token, 300e18);
        TransientReceiver receiver = new TransientReceiver();
        receiver.configure(100e18, lender, 200e18);

        vm.prank(minter);
        token.transfer(address(receiver), 300e18);

        // During the hook, the receiver held the tokens transiently.
        assertEq(receiver.observedBalance(), 300e18, "transient balance");
        assertEq(receiver.observedTransientSupply(), 300e18, "transient supply");
        // After the hook, everything is settled.
        assertEq(loanToken.balanceOf(address(receiver)), 100e18, "redeemed");
        assertEq(token.balanceOf(address(receiver)), 0, "transient balance cleared");
        assertEq(token.balanceOf(lender), 200e18, "lender balance");
        assertEq(token.transientSupply(), 0, "transient supply cleared");
        assertEq(token.totalSupply(), 200e18, "total supply");
    }

    function testTransientReceiverMustSettle() public {
        _mint(300e18);
        _pay(token, 300e18);
        TransientReceiver receiver = new TransientReceiver();
        receiver.configure(100e18, lender, 100e18); // leaves 100 behind.

        vm.prank(minter);
        vm.expectRevert(IReceivableToken.TransientBalanceNotSettled.selector);
        token.transfer(address(receiver), 300e18);
    }

    function testNonWhitelistedAccountWithoutCodeCannotReceive() public {
        _mint(1);
        vm.prank(minter);
        vm.expectRevert();
        token.transfer(stranger, 1);
    }

    function testPermissionlessFlashLiquidation() public {
        // Market with a liquidation incentive, so the liquidator earns something.
        Market memory market = _market(LLTV);
        bytes32 id = toId(market);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        _pay(token, collateral);

        // A non-whitelisted liquidator with no capital liquidates after the incentive has fully ramped up.
        vm.warp(maturity + 1 hours);
        FlashLiquidator flashLiquidator = new FlashLiquidator(address(midnight));
        uint256 seized = units.mulDivDown(maxLif(LLTV, LIQUIDATION_CURSOR), WAD);
        vm.expectEmit(address(token));
        emit IReceivableToken.Transfer(address(flashLiquidator), address(0), seized);
        flashLiquidator.liquidate(market, units, minter);
        assertEq(midnight.debt(id, minter), 0, "debt repaid");
        assertEq(midnight.collateral(id, minter, 0), collateral - seized, "collateral seized");
        assertEq(loanToken.balanceOf(address(flashLiquidator)), seized - units, "liquidator profit");
        assertEq(token.balanceOf(address(flashLiquidator)), 0, "liquidator holds no token");
        assertEq(token.transientSupply(), 0, "no transient tokens left");
        assertEq(token.totalSupply(), collateral - seized, "supply");
        assertEq(midnight.withdrawable(id), units, "lender can withdraw");
    }

    function testNonWhitelistedLiquidatorCannotKeepCollateral() public {
        Market memory market = _market(LLTV);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);
        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        _pay(token, collateral);
        vm.warp(maturity + 1 hours);

        // A liquidator contract that does not dispose of the seized tokens in the hook.
        FlashLiquidator flashLiquidator = new FlashLiquidator(address(midnight));
        flashLiquidator.setKeep(true);
        vm.expectRevert(IReceivableToken.TransientBalanceNotSettled.selector);
        flashLiquidator.liquidate(market, units, minter);

        // A plain address, which cannot implement the hook.
        deal(address(loanToken), liquidator, units);
        vm.prank(liquidator);
        vm.expectRevert();
        midnight.liquidate(market, 0, 0, units, minter, true, liquidator, address(0), "");

        // The position is untouched, and the same liquidator succeeds once it settles.
        assertEq(midnight.debt(toId(market), minter), units, "debt untouched");
        flashLiquidator.setKeep(false);
        flashLiquidator.liquidate(market, units, minter);
        assertEq(midnight.debt(toId(market), minter), 0, "debt repaid");
        assertEq(token.balanceOf(address(flashLiquidator)), 0, "liquidator holds no token");
    }

    function testMidnightAlwaysWhitelisted() public {
        Market memory market = _market();
        bytes32 id = toId(market);
        uint256 collateral = 100e18;

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        assertEq(token.balanceOf(address(midnight)), collateral, "midnight balance");

        // Midnight is whitelisted without ever proving a leaf.
        assertTrue(token.isWhitelisted(address(midnight)), "midnight whitelisted");

        vm.prank(minter);
        midnight.withdrawCollateral(market, 0, collateral, minter, minter);
        assertEq(midnight.collateral(id, minter, 0), 0, "collateral withdrawn");
        assertEq(token.balanceOf(minter), collateral, "borrower got the tokens back");
    }

    function testMarkdownMakesPositionsLiquidatable() public {
        // A market using the token itself as the collateral oracle.
        Market memory market = _market(LLTV, address(token));
        bytes32 id = toId(market);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        assertTrue(midnight.isHealthy(market, id, minter), "healthy at par");

        // The owner marks the rate down and the position becomes liquidatable before maturity.
        vm.prank(minter);
        token.setRate(WAD / 2);
        assertFalse(midnight.isHealthy(market, id, minter), "unhealthy after markdown");

        // A (0, 0) liquidation realizes the bad debt without seizing collateral.
        uint256 lossFactorBefore = midnight.lossFactor(id);
        vm.prank(liquidator);
        midnight.liquidate(market, 0, 0, 0, minter, false, address(midnight), address(0), "");
        assertLt(midnight.debt(id, minter), units, "bad debt realized");
        assertGt(midnight.lossFactor(id), lossFactorBefore, "loss factor increased");
    }

    /// MIDNIGHT FLOW ///

    function testBorrowOnMidnightAndLiquidateAfterMaturity() public {
        Market memory market = _market();
        bytes32 id = toId(market);
        uint256 units = 600e18;

        // The minter mints receivable tokens, pledges them and sells debt.
        _mint(units);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, units, minter);
        (, uint256 sellerAssets) = take(units, minter, _buyOffer(market));
        assertEq(midnight.debt(id, minter), units, "debt");
        assertEq(sellerAssets, units.mulDivDown(TickLib.tickToPrice(TICK), WAD), "proceeds");
        assertEq(loanToken.balanceOf(minter), sellerAssets, "minter balance");

        // The receipts arrive, backing the collateral.
        _pay(token, units);
        assertEq(token.cash(), units, "cash");

        // After maturity, a whitelisted liquidator repays the debt, seizes the collateral and redeems it at face.
        vm.warp(maturity + 1);
        _whitelistLiquidator();
        deal(address(loanToken), liquidator, units);
        vm.prank(liquidator);
        (uint256 seized, uint256 repaid) =
            midnight.liquidate(market, 0, 0, units, minter, true, liquidator, address(0), "");
        assertEq(repaid, units, "repaid");
        assertEq(seized, units, "seized");
        assertEq(midnight.debt(id, minter), 0, "debt repaid");

        vm.prank(liquidator);
        token.redeem(seized, liquidator);
        assertEq(loanToken.balanceOf(liquidator), units, "liquidator cash");
        assertEq(midnight.withdrawable(id), units, "lender can withdraw");
    }
}

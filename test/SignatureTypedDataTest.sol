// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

// Paste from eth_signTypedData_v4 output.
address constant ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
uint8 constant SIG_V = 27;
bytes32 constant SIG_R = 0x09a648ee294a2ca00ab473404851f03f6e6b884678040da1bd795be8f9773609;
bytes32 constant SIG_S = 0x47caf1e2a1527357e5ae0091100f7de32b469916c05e163ecf5b46f0f0ab693d;

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
uint256 constant HEIGHT = 2;

contract SignatureTypedDataTest is Test {
    function setUp() public {
        vm.chainId(1);
        EcrecoverRatifier impl = new EcrecoverRatifier(address(this));
        vm.etch(RATIFIER, address(impl).code);
    }

    function defaultOffer(uint8 number) internal pure returns (Offer memory offer) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        offer.obligation.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.obligation.collateralParams = collateralParams;
        offer.expiry = 2 ** 32;
        offer.ratifier = RATIFIER;
    }

    function testTypedDataV4SignatureVerification() public view {
        Offer[4] memory offers;
        offers[0] = defaultOffer(1);
        offers[1] = defaultOffer(2);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(4);

        bytes32 _root = root(offers);
        bytes32 structHash = keccak256(abi.encode(UtilsLib.offerTreeTypeHash(HEIGHT), _root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, RATIFIER));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        assertEq(vm.eip712HashTypedData(typedData()), digest);
        assertEq(ecrecover(digest, SIG_V, SIG_R, SIG_S), ACCOUNT);

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), HEIGHT);
        // Trick to pass the maker to the ratifier, without having the offers depend on the maker.
        offers[0].maker = ACCOUNT;
        bytes32 result = EcrecoverRatifier(RATIFIER).onRatify(offers[0], _root, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function root(Offer[4] memory offers) internal pure returns (bytes32) {
        bytes32 left = UtilsLib.commutativeHash(UtilsLib.hashOffer(offers[0]), UtilsLib.hashOffer(offers[1]));
        bytes32 right = UtilsLib.commutativeHash(UtilsLib.hashOffer(offers[2]), UtilsLib.hashOffer(offers[3]));
        return UtilsLib.commutativeHash(left, right);
    }

    function typedData() internal pure returns (string memory) {
        return string.concat(
            '{"types":{"EIP712Domain":[{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],',
            '"OfferTree":[{"name":"offerTree","type":"Offer[2][2]"}],',
            '"CollateralParams":[{"name":"token","type":"address"},{"name":"lltv","type":"uint256"},{"name":"maxLif","type":"uint256"},{"name":"oracle","type":"address"}],',
            '"Obligation":[{"name":"loanToken","type":"address"},{"name":"collateralParams","type":"CollateralParams[]"},{"name":"maturity","type":"uint256"},{"name":"rcfThreshold","type":"uint256"},{"name":"enterGate","type":"address"},{"name":"liquidatorGate","type":"address"}],',
            '"Offer":[{"name":"obligation","type":"Obligation"},{"name":"buy","type":"bool"},{"name":"maker","type":"address"},{"name":"start","type":"uint256"},{"name":"expiry","type":"uint256"},{"name":"tick","type":"uint256"},{"name":"group","type":"bytes32"},{"name":"session","type":"bytes32"},{"name":"callback","type":"address"},{"name":"callbackData","type":"bytes"},{"name":"receiverIfMakerIsSeller","type":"address"},{"name":"ratifier","type":"address"},{"name":"reduceOnly","type":"bool"},{"name":"maxUnits","type":"uint256"},{"name":"maxSellerAssets","type":"uint256"},{"name":"maxBuyerAssets","type":"uint256"}]},',
            '"primaryType":"OfferTree","domain":{"chainId":1,"verifyingContract":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},',
            '"message":{"offerTree":[[',
            offerJson("0x1111111111111111111111111111111111111111"),
            ",",
            offerJson("0x2222222222222222222222222222222222222222"),
            "],[",
            offerJson("0x3333333333333333333333333333333333333333"),
            ",",
            offerJson("0x4444444444444444444444444444444444444444"),
            "]]}}"
        );
    }

    function offerJson(string memory loanToken) internal pure returns (string memory) {
        return string.concat(
            '{"obligation":{"loanToken":"',
            loanToken,
            '","collateralParams":[{"token":"0x0000000000000000000000000000000000000000","lltv":"0","maxLif":"0","oracle":"0x0000000000000000000000000000000000000000"}],',
            '"maturity":"0","rcfThreshold":"0","enterGate":"0x0000000000000000000000000000000000000000","liquidatorGate":"0x0000000000000000000000000000000000000000"},',
            '"buy":false,"maker":"0x0000000000000000000000000000000000000000","start":"0","expiry":"4294967296","tick":"0",',
            '"group":"0x0000000000000000000000000000000000000000000000000000000000000000","session":"0x0000000000000000000000000000000000000000000000000000000000000000",',
            '"callback":"0x0000000000000000000000000000000000000000","callbackData":"0x","receiverIfMakerIsSeller":"0x0000000000000000000000000000000000000000",',
            '"ratifier":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB","reduceOnly":false,"maxUnits":"0","maxSellerAssets":"0","maxBuyerAssets":"0"}'
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import "../src/Terms.sol";

abstract contract BaseTest is Test {
    Terms internal terms;

    function setUp() public virtual {
        terms = new Terms();
    }

    function _signOffer(Offer memory offer, uint256 sk) internal view returns (Signature memory) {
        bytes32 hashStruct = keccak256(abi.encode(terms.OFFER_TYPEHASH(), offer));
        bytes32 domainSeparator = keccak256(abi.encode(terms.DOMAIN_TYPEHASH(), block.chainid, address(terms)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(sk, digest);
        return sig;
    }

    function sortTokens(ERC20[] memory arr) internal pure returns (ERC20[] memory) {
        uint256 length = arr.length;
        for (uint256 i = 1; i < length; i++) {
            bytes20 key = bytes20((address(arr[i])));
            uint256 j = i - 1;
            while ((int256(j) >= 0) && (bytes20(address(arr[j])) > key)) {
                arr[j + 1] = arr[j];
                if (j == 0) {
                    break;
                }
                j--;
            }
            arr[j + (bytes20(address(arr[j])) > key ? 0 : 1)] = ERC20(address(key));
        }
        return arr;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {IMorpho, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IrmMock} from "../lib/morpho-blue/src/mocks/IrmMock.sol";
import "../src/Terms.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract TermsTest is Test {
    Terms private terms;
    ERC20 private loanToken;
    ERC20 private collateralToken;
    Oracle private oracle;
    uint256 private borrowerSK;
    address private borrower;
    uint256 private lenderSK;
    address private lender;
    Term private term;
    bytes32 private id;
    Collateral[] private collaterals;

    IMorpho private morpho;
    IrmMock private irm;
    MarketParams private marketParams;

    function setUp() external {
        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");

        // Morpho bonds setup
        terms = new Terms();
        loanToken = new ERC20("loan", "loan", 1 ether);
        loanToken.transfer(lender, 99);
        loanToken.transfer(borrower, 1);
        collateralToken = new ERC20("collat", "collat", 1 ether);
        oracle = new Oracle();

        collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(collateralToken), lltv: 1e18, oracle: address(oracle)});

        term = Term(address(loanToken), collaterals, block.timestamp + 100);
        id = keccak256(abi.encode(term));

        vm.prank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        collateralToken.approve(address(terms), type(uint256).max);
        terms.supplyCollateral(term, address(collateralToken), 1 ether, borrower);

        // Morpho blue setup
        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));
        irm = new IrmMock();

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            oracle: address(oracle),
            lltv: 0.8 ether
        });

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.8 ether);
        vm.stopPrank();

        morpho.createMarket(marketParams);

        vm.startPrank(lender);
        loanToken.approve(address(morpho), type(uint256).max);
        morpho.supply(marketParams, 99, 0, lender, hex"");
        morpho.setAuthorization(address(terms), true);
    }

    function testMorphoCallback() public {
        Callback memory callback = Callback({
            callbackAddress: address(morpho),
            callbackData: abi.encodeWithSelector(
                //"withdraw((address,address,address,address,uint256),uin256,uin256,address,address)",
                0x5c2bea49,
                marketParams,
                99,
                0,
                lender,
                lender
            ),
            callbackGasLimit: 1_000_000
        });
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99,
            callback: callback
        });
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99,
            callback: Callback({callbackAddress: address(0), callbackData: hex"", callbackGasLimit: 0})
        });

        Signature memory lendSig = _signOffer(lendOffer, lenderSK);
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        terms.MATCH(lendOffer, lendSig, borrowOffer, borrowSig);

        assertEq(terms.bondOf(lender, id), 100);
        assertEq(terms.debtOf(borrower, id), 100);

        assertEq(loanToken.balanceOf(borrower), 100);
        assertEq(loanToken.balanceOf(lender), 0);
    }

    function _signOffer(Offer memory offer, uint256 sk) internal view returns (Signature memory) {
        bytes32 hashStruct = keccak256(abi.encode(terms.OFFER_TYPEHASH(), offer));
        bytes32 domainSeparator = keccak256(abi.encode(terms.DOMAIN_TYPEHASH(), block.chainid, address(terms)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(sk, digest);
        return sig;
    }
}

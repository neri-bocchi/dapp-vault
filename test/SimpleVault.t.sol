// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {SimpleVault} from "../src/SimpleVault.sol";

contract SimpleVaultTest is Test {
    MockUSDC internal usdc;
    SimpleVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    // 1 mUSDC = 1e6 unidades; con offset 6, al inicio 1 unidad de activo = 1e6 shares.
    uint256 internal constant OFFSET = 1e6;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new SimpleVault(usdc);
    }

    function _deposit(address user, uint256 assets) internal returns (uint256 shares) {
        usdc.mint(user, assets);
        vm.startPrank(user);
        usdc.approve(address(vault), assets);
        shares = vault.deposit(assets, user);
        vm.stopPrank();
    }

    function test_Metadata() public view {
        assertEq(vault.name(), "Simple Vault mUSDC");
        assertEq(vault.symbol(), "svUSDC");
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.decimals(), 12);
    }

    function test_Deposit() public {
        uint256 shares = _deposit(alice, 100e6);

        assertEq(shares, 100e6 * OFFSET);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), 100e6);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_Mint() public {
        uint256 shares = 50e6 * OFFSET;
        uint256 assets = vault.previewMint(shares);
        usdc.mint(alice, assets);

        vm.startPrank(alice);
        usdc.approve(address(vault), assets);
        uint256 pagado = vault.mint(shares, alice);
        vm.stopPrank();

        assertEq(pagado, 50e6);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_Withdraw() public {
        _deposit(alice, 100e6);

        vm.prank(alice);
        uint256 quemadas = vault.withdraw(30e6, alice, alice);

        assertEq(quemadas, 30e6 * OFFSET);
        assertEq(usdc.balanceOf(alice), 30e6);
        assertEq(vault.totalAssets(), 70e6);
    }

    function test_Redeem() public {
        uint256 shares = _deposit(alice, 100e6);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertEq(assets, 100e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), 100e6);
    }

    function test_WithdrawConAllowance() public {
        uint256 shares = _deposit(alice, 100e6);

        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.redeem(shares, bob, alice);

        assertEq(usdc.balanceOf(bob), 100e6);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_RevertSi_RetiraSinAllowance() public {
        _deposit(alice, 100e6);

        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(10e6, bob, alice);
    }

    function test_RendimientoSeRepartePorShares() public {
        _deposit(alice, 100e6);
        _deposit(bob, 300e6);

        // Simula rendimiento: el vault recibe 40 mUSDC sin emitir shares.
        usdc.mint(address(vault), 40e6);

        // El redondeo de OZ favorece al vault: como mucho 1 unidad de diferencia.
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(alice)), 110e6, 1);
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(bob)), 330e6, 1);
    }

    function testFuzz_DepositRedeemNoGanaActivos(uint256 assets) public {
        assets = bound(assets, 1, 1e15); // hasta 1.000 millones de mUSDC
        uint256 shares = _deposit(alice, assets);

        vm.prank(alice);
        uint256 recuperado = vault.redeem(shares, alice, alice);

        assertLe(recuperado, assets);
    }

    function testFuzz_PreviewDepositCoincide(uint256 assets) public {
        assets = bound(assets, 1, 1e15);
        _deposit(bob, 123e6);

        uint256 esperado = vault.previewDeposit(assets);
        uint256 shares = _deposit(alice, assets);

        assertEq(shares, esperado);
    }

    /// @notice Ataque de inflación: el atacante deposita 1 unidad y luego dona
    /// una gran cantidad para que el depósito de la víctima redondee a 0 shares.
    /// Con offset 6 la víctima conserva casi todo su depósito.
    function test_AtaqueDeInflacionMitigado() public {
        _deposit(attacker, 1);
        usdc.mint(attacker, 10_000e6);
        vm.prank(attacker);
        usdc.transfer(address(vault), 10_000e6);

        uint256 sharesVictima = _deposit(alice, 1_000e6);
        assertGt(sharesVictima, 0);

        vm.prank(alice);
        uint256 recuperado = vault.redeem(sharesVictima, alice, alice);

        // La víctima pierde menos del 0,01 %.
        assertApproxEqRel(recuperado, 1_000e6, 0.0001e18);
    }
}

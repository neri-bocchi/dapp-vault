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
    // Tope de los fuzz: 1.000 millones de mUSDC.
    uint256 internal constant MAX_ASSETS = 1e15;

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

    /// @dev Simula rendimiento: el vault recibe activos sin emitir shares.
    function _donate(uint256 assets) internal {
        usdc.mint(address(vault), assets);
    }

    // ---------------------------------------------------------------
    // Unitarios
    // ---------------------------------------------------------------

    function test_Metadata() public view {
        assertEq(vault.name(), "Simple Vault mUSDC");
        assertEq(vault.symbol(), "svUSDC");
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.decimals(), 12);
    }

    function test_Deposit() public {
        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(vault), 100e6);
        uint256 shares = vault.deposit(100e6, alice);
        vm.stopPrank();

        assertEq(shares, 100e6 * OFFSET);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), 100e6);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_DepositAOtroReceptor() public {
        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(vault), 100e6);
        uint256 shares = vault.deposit(100e6, bob);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), shares);
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
        assertEq(vault.totalAssets(), 50e6);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_MintRedondeaHaciaArribaConRendimiento() public {
        _deposit(bob, 100e6);
        _donate(1e6 + 1); // precio por share deja de ser exacto

        uint256 shares = 1;
        uint256 assets = vault.previewMint(shares);
        // Ceil: aunque 1 share vale una fracción de unidad, se paga al menos 1.
        assertEq(assets, 1);
    }

    function test_Withdraw() public {
        _deposit(alice, 100e6);

        vm.prank(alice);
        uint256 quemadas = vault.withdraw(30e6, alice, alice);

        assertEq(quemadas, 30e6 * OFFSET);
        assertEq(vault.balanceOf(alice), 70e6 * OFFSET);
        assertEq(usdc.balanceOf(alice), 30e6);
        assertEq(vault.totalAssets(), 70e6);
    }

    function test_WithdrawConAllowance() public {
        _deposit(alice, 100e6);
        uint256 necesarias = vault.previewWithdraw(100e6);

        vm.prank(alice);
        vault.approve(bob, necesarias);

        vm.prank(bob);
        vault.withdraw(100e6, bob, alice);

        assertEq(usdc.balanceOf(bob), 100e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_RevertSi_WithdrawSinAllowance() public {
        _deposit(alice, 100e6);

        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(10e6, bob, alice);
    }

    function test_RevertSi_WithdrawMasQueMax() public {
        _deposit(alice, 100e6);
        uint256 max = vault.maxWithdraw(alice);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(max + 1, alice, alice);
    }

    function test_Redeem() public {
        uint256 shares = _deposit(alice, 100e6);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertEq(assets, 100e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(usdc.balanceOf(alice), 100e6);
    }

    function test_RedeemConAllowance() public {
        uint256 shares = _deposit(alice, 100e6);

        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.redeem(shares, bob, alice);

        assertEq(usdc.balanceOf(bob), 100e6);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_RevertSi_RedeemMasQueBalance() public {
        uint256 shares = _deposit(alice, 100e6);

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares + 1, alice, alice);
    }

    function test_RendimientoSeRepartePorShares() public {
        _deposit(alice, 100e6);
        _deposit(bob, 300e6);
        _donate(40e6);

        // El redondeo favorece al vault: como mucho 1 unidad de diferencia.
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(alice)), 110e6, 1);
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(bob)), 330e6, 1);
    }

    // ---------------------------------------------------------------
    // Fuzz: preview* coincide con la acción real
    // ---------------------------------------------------------------

    function testFuzz_PreviewDepositIgualDeposit(uint256 previo, uint256 rendimiento, uint256 assets) public {
        previo = bound(previo, 0, MAX_ASSETS);
        rendimiento = bound(rendimiento, 0, MAX_ASSETS);
        assets = bound(assets, 1, MAX_ASSETS);

        if (previo > 0) _deposit(bob, previo);
        _donate(rendimiento);

        uint256 esperado = vault.previewDeposit(assets);
        vm.assume(esperado > 0);
        uint256 shares = _deposit(alice, assets);

        assertEq(shares, esperado);
    }

    function testFuzz_PreviewRedeemIgualRedeem(uint256 depositado, uint256 rendimiento, uint256 shares) public {
        depositado = bound(depositado, 1, MAX_ASSETS);
        rendimiento = bound(rendimiento, 0, MAX_ASSETS);

        _deposit(bob, 123e6);
        uint256 recibidas = _deposit(alice, depositado);
        _donate(rendimiento);
        shares = bound(shares, 1, recibidas);

        uint256 esperado = vault.previewRedeem(shares);
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertEq(assets, esperado);
        assertEq(usdc.balanceOf(alice), esperado);
    }

    function testFuzz_DepositRedeemNoGanaActivos(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS);
        uint256 shares = _deposit(alice, assets);

        vm.prank(alice);
        uint256 recuperado = vault.redeem(shares, alice, alice);

        assertLe(recuperado, assets);
    }

    // ---------------------------------------------------------------
    // Ataque al primer depositante (inflación)
    // ---------------------------------------------------------------

    /// @notice El atacante deposita 1 unidad, dona una gran cantidad para inflar el
    /// precio de la share y espera que el depósito de la víctima redondee a (casi) 0.
    /// Con offset 6 las shares virtuales se quedan con la mayor parte de la donación:
    /// el atacante pierde dinero y la víctima conserva su depósito.
    function test_AtaqueAlPrimerDepositanteNoEsRentable() public {
        uint256 donacion = 10_000e6;
        uint256 depositoVictima = 1_000e6;

        // 1. Depósito mínimo + donación directa al vault.
        uint256 sharesAtacante = _deposit(attacker, 1);
        usdc.mint(attacker, donacion);
        vm.prank(attacker);
        usdc.transfer(address(vault), donacion);
        uint256 gastado = 1 + donacion;

        // 2. La víctima deposita y recibe shares.
        uint256 sharesVictima = _deposit(alice, depositoVictima);
        assertGt(sharesVictima, 0);

        // 3. Ambos retiran todo.
        vm.prank(attacker);
        uint256 recuperadoAtacante = vault.redeem(sharesAtacante, attacker, attacker);
        vm.prank(alice);
        uint256 recuperadoVictima = vault.redeem(sharesVictima, alice, alice);

        // El atacante pierde ~50 % de lo que puso: las shares virtuales (10 ** 6)
        // valen tanto como las suyas y absorben la mitad de la donación.
        assertLt(recuperadoAtacante, (gastado * 51) / 100);
        // La víctima pierde menos del 0,01 %.
        assertApproxEqRel(recuperadoVictima, depositoVictima, 0.0001e18);
    }

    function testFuzz_AtaqueAlPrimerDepositanteNoEsRentable(
        uint256 depositoAtacante,
        uint256 donacion,
        uint256 depositoVictima
    ) public {
        depositoAtacante = bound(depositoAtacante, 1, 1e6);
        donacion = bound(donacion, 1, MAX_ASSETS);
        depositoVictima = bound(depositoVictima, 1, MAX_ASSETS);

        uint256 sharesAtacante = _deposit(attacker, depositoAtacante);
        _donate(donacion); // equivale a que el atacante transfiera al vault
        uint256 gastado = depositoAtacante + donacion;

        vm.assume(vault.previewDeposit(depositoVictima) > 0);
        _deposit(alice, depositoVictima);

        vm.prank(attacker);
        uint256 recuperado = vault.redeem(sharesAtacante, attacker, attacker);

        assertLt(recuperado, gastado);
    }
}

// -------------------------------------------------------------------
// Invariante: lo que valen todas las shares nunca supera totalAssets
// -------------------------------------------------------------------

/// @dev Handler que el fuzzer usa para llamar al vault con entradas acotadas.
contract VaultHandler is Test {
    MockUSDC internal usdc;
    SimpleVault internal vault;
    address[] internal actores;

    constructor(MockUSDC usdc_, SimpleVault vault_) {
        usdc = usdc_;
        vault = vault_;
        actores.push(makeAddr("actor1"));
        actores.push(makeAddr("actor2"));
        actores.push(makeAddr("actor3"));
    }

    function actoresLength() external view returns (uint256) {
        return actores.length;
    }

    function actor(uint256 i) external view returns (address) {
        return actores[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actores[seed % actores.length];
    }

    function deposit(uint256 seed, uint256 assets) external {
        address a = _actor(seed);
        assets = bound(assets, 1, 1e15);
        if (vault.previewDeposit(assets) == 0) return;

        usdc.mint(a, assets);
        vm.startPrank(a);
        usdc.approve(address(vault), assets);
        vault.deposit(assets, a);
        vm.stopPrank();
    }

    function mint(uint256 seed, uint256 shares) external {
        address a = _actor(seed);
        shares = bound(shares, 1, 1e21);
        uint256 assets = vault.previewMint(shares);

        usdc.mint(a, assets);
        vm.startPrank(a);
        usdc.approve(address(vault), assets);
        vault.mint(shares, a);
        vm.stopPrank();
    }

    function withdraw(uint256 seed, uint256 assets) external {
        address a = _actor(seed);
        uint256 max = vault.maxWithdraw(a);
        if (max == 0) return;
        assets = bound(assets, 1, max);

        vm.prank(a);
        vault.withdraw(assets, a, a);
    }

    function redeem(uint256 seed, uint256 shares) external {
        address a = _actor(seed);
        uint256 max = vault.maxRedeem(a);
        if (max == 0) return;
        shares = bound(shares, 1, max);

        vm.prank(a);
        vault.redeem(shares, a, a);
    }

    /// @dev Rendimiento externo: activos que llegan al vault sin emitir shares.
    function donate(uint256 assets) external {
        assets = bound(assets, 0, 1e13);
        usdc.mint(address(vault), assets);
    }
}

contract SimpleVaultInvariantTest is Test {
    MockUSDC internal usdc;
    SimpleVault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new SimpleVault(usdc);
        handler = new VaultHandler(usdc, vault);
        targetContract(address(handler));
    }

    /// @notice Valuadas en conjunto, las shares en circulación no pueden reclamar
    /// más activos de los que el vault tiene.
    function invariant_SharesNoValenMasQueTotalAssets() public view {
        assertLe(vault.convertToAssets(vault.totalSupply()), vault.totalAssets());
    }

    /// @notice Lo mismo sumando lo que cada holder puede retirar realmente.
    function invariant_SumaDeMaxWithdrawNoSuperaTotalAssets() public view {
        uint256 suma;
        for (uint256 i; i < handler.actoresLength(); i++) {
            suma += vault.maxWithdraw(handler.actor(i));
        }
        assertLe(suma, vault.totalAssets());
    }

    /// @notice totalAssets es exactamente el balance de mUSDC del vault.
    function invariant_TotalAssetsIgualBalance() public view {
        assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
    }
}

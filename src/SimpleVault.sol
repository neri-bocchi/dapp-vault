// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title SimpleVault
/// @notice Vault ERC-4626 sobre un único activo. Toda la matemática la provee OpenZeppelin v5;
/// este contrato no sobrescribe ninguna función de conversión, preview ni acción.
/// @dev Redondeo (heredado de OZ ERC4626). Regla general: siempre a favor del vault,
/// es decir, en contra del usuario que interactúa. Así nadie puede extraer valor de los
/// demás depositantes repitiendo operaciones que redondean a su favor (EIP-4626, "Security").
///
/// - `convertToShares(assets)`: hacia abajo (Floor). Valor informativo; conservador para el usuario.
/// - `convertToAssets(shares)`: hacia abajo (Floor). Idem.
/// - `previewDeposit(assets)` / `deposit`: shares hacia abajo (Floor). El usuario entrega
///   activos exactos y recibe como mucho las shares que le corresponden.
/// - `previewMint(shares)` / `mint`: activos hacia arriba (Ceil). El usuario pide shares
///   exactas y paga como mínimo los activos que valen.
/// - `previewWithdraw(assets)` / `withdraw`: shares hacia arriba (Ceil). El usuario retira
///   activos exactos y quema como mínimo las shares necesarias.
/// - `previewRedeem(shares)` / `redeem`: activos hacia abajo (Floor). El usuario quema
///   shares exactas y recibe como mucho los activos que valen.
/// - `maxWithdraw(owner)`: `previewRedeem(balanceOf(owner))`, por lo tanto Floor.
/// - `maxRedeem(owner)`: `balanceOf(owner)`, sin redondeo.
///
/// Las conversiones usan `totalSupply() + 10 ** _decimalsOffset()` y `totalAssets() + 1`
/// (shares y activos virtuales), lo que además evita la división por cero con el vault vacío.
contract SimpleVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Simple Vault mUSDC", "svUSDC") ERC4626(asset_) {}

    /// @dev Offset de decimales contra el ataque de inflación: las shares tienen
    /// decimales del activo + 6 (12 para mUSDC).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}

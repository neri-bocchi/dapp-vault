// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title SimpleVault
/// @notice Vault ERC-4626 sobre un único activo. Toda la matemática la provee OpenZeppelin.
contract SimpleVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Simple Vault mUSDC", "svUSDC") ERC4626(asset_) {}

    /// @dev Offset de decimales contra el ataque de inflación: las shares tienen
    /// decimales del activo + 6 (12 para mUSDC).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}

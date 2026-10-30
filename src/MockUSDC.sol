// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Token ERC-20 de prueba con 6 decimales, como USDC.
/// @dev Solo para desarrollo local: cualquiera puede mintear.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USD Coin", "mUSDC") {}

    /// @notice USDC usa 6 decimales en lugar de los 18 por defecto.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint público, sin control de acceso.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

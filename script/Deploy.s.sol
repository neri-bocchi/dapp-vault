// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {SimpleVault} from "../src/SimpleVault.sol";

/// @notice Despliega MockUSDC y SimpleVault en Anvil, mintea 10.000 mUSDC al deployer
/// y guarda las direcciones en web/src/addresses.json para el frontend.
/// Uso: forge script script/Deploy.s.sol --rpc-url anvil --private-key $PRIVATE_KEY --broadcast
contract Deploy is Script {
    uint256 internal constant MINT_INICIAL = 10_000e6;
    string internal constant ADDRESSES_PATH = "web/src/addresses.json";

    function run() external returns (MockUSDC usdc, SimpleVault vault) {
        require(block.chainid == 31337, "Deploy: solo para Anvil (chainId 31337)");

        vm.startBroadcast();
        usdc = new MockUSDC();
        vault = new SimpleVault(usdc);
        usdc.mint(msg.sender, MINT_INICIAL);
        vm.stopBroadcast();

        _guardarDirecciones(address(usdc), address(vault));

        console.log("MockUSDC:   ", address(usdc));
        console.log("SimpleVault:", address(vault));
        console.log("Deployer:   ", msg.sender);
        console.log("Direcciones guardadas en", ADDRESSES_PATH);
    }

    function _guardarDirecciones(address usdc, address vault) internal {
        string memory key = "addresses";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "mockUSDC", usdc);
        string memory json = vm.serializeAddress(key, "simpleVault", vault);

        // web/src puede no existir todavía si el frontend no está scaffoldeado.
        vm.createDir(string.concat(vm.projectRoot(), "/web/src"), true);
        vm.writeJson(json, string.concat(vm.projectRoot(), "/", ADDRESSES_PATH));
    }
}

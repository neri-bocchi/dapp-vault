// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {SimpleVault} from "../src/SimpleVault.sol";

/// @notice Despliega MockUSDC y SimpleVault en Anvil y mintea 10.000 mUSDC al deployer.
/// Uso: forge script script/Deploy.s.sol --rpc-url anvil --private-key $PRIVATE_KEY --broadcast
contract Deploy is Script {
    uint256 internal constant MINT_INICIAL = 10_000e6;

    function run() external returns (MockUSDC usdc, SimpleVault vault) {
        require(block.chainid == 31337, "Deploy: solo para Anvil (chainId 31337)");

        vm.startBroadcast();
        usdc = new MockUSDC();
        vault = new SimpleVault(usdc);
        usdc.mint(msg.sender, MINT_INICIAL);
        vm.stopBroadcast();

        console.log("MockUSDC:   ", address(usdc));
        console.log("SimpleVault:", address(vault));
        console.log("Deployer:   ", msg.sender);
    }
}

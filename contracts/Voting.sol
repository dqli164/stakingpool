// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract VotingV2 {

    function upgrade(address proxyAddress, address proxyAdminAddress, address newImplementation) external {
        // Assuming you have already transferred ProxyAdmin ownership to this contract
        // Set the actual ProxyAdmin address

        // Create a new TransparentUpgradeableProxy instance
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);

        // Upgrade the proxy to the new implementation
        ProxyAdmin(proxyAdminAddress).upgradeAndCall(proxy, newImplementation, bytes(""));
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";

contract DeploySmartnodes is Script {
    function run() external returns (SmartnodesCore) {
        address[] memory validators;
        validators[0] = 0x1234567890123456789012345678901234567890;
        validators[1] = 0x0987654321098765432109876543210987654321;

        vm.startBroadcast();
        SmartnodesCore smartnodesCore = new SmartnodesCore(validators);
        vm.startBroadcast();
        return smartnodesCore;
    }
}

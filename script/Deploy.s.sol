// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";

contract Deploy is Script {
    address[] genesis;

    function run() external {
        genesis.push(msg.sender);

        vm.startBroadcast();

        SmartnodesToken token = new SmartnodesToken(genesis);
        SmartnodesCore core = new SmartnodesCore(address(token));
        SmartnodesCoordinator coordinator = new SmartnodesCoordinator(
            3600,
            66,
            address(core),
            genesis
        );
        SmartnodesDAO dao = new SmartnodesDAO(address(token), address(core));

        token.setSmartnodesCore(address(core));
        core.setCoordinator(address(coordinator));

        token.transferOwnership(msg.sender);
        dao.transferOwnership(msg.sender);

        console.log("Token:", address(token));
        console.log("Core:", address(core));
        console.log("Coordinator:", address(coordinator));
        console.log("DAO:", address(dao));

        vm.stopBroadcast();
    }
}

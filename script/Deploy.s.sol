// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";

uint256 constant DAO_VOTING_PERIOD = 7 days;

contract Deploy is Script {
    address[] genesis;
    address[] initialActiveNodes;

    function run() external {
        genesis.push(msg.sender);
        genesis.push(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        vm.startBroadcast();

        SmartnodesToken token = new SmartnodesToken(genesis);
        SmartnodesDAO dao = new SmartnodesDAO(
            address(token),
            DAO_VOTING_PERIOD
        );
        SmartnodesCore core = new SmartnodesCore(address(token));

        token.setDAO(address(dao));

        SmartnodesCoordinator coordinator = new SmartnodesCoordinator(
            3600,
            66,
            address(core),
            address(token),
            initialActiveNodes
        );

        token.setSmartnodes(address(core), address(coordinator));
        core.setCoordinator(address(coordinator));

        bytes32 publicKeyHash = vm.envBytes32("PUBLIC_KEY_HASH");

        core.createValidator(publicKeyHash);
        coordinator.addValidator();

        console.log("Token:", address(token));
        console.log("Core:", address(core));
        console.log("Coordinator:", address(coordinator));
        console.log("DAO:", address(dao));

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {SmartnodesERC20} from "../src/SmartnodesERC20.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";

uint256 constant DAO_VOTING_PERIOD = 7 days;
uint256 constant DEPLOYMENT_MULTIPLIER = 1;
uint256 constant INTERVAL_SECONDS = 1 hours;

contract Deploy is Script {
    address[] genesis;
    address[] initialActiveNodes;

    function run() external {
        genesis.push(msg.sender);
        genesis.push(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        vm.startBroadcast();

        SmartnodesERC20 token = new SmartnodesERC20(
            DEPLOYMENT_MULTIPLIER,
            genesis
        );
        SmartnodesDAO dao = new SmartnodesDAO(
            address(token),
            DAO_VOTING_PERIOD,
            1000
        );
        SmartnodesCore core = new SmartnodesCore(address(token));
        SmartnodesCoordinator coordinator = new SmartnodesCoordinator(
            uint128(INTERVAL_SECONDS * DEPLOYMENT_MULTIPLIER),
            66,
            address(core),
            address(token),
            initialActiveNodes
        );

        token.setSmartnodes(address(core), address(coordinator));

        token.setDAO(address(dao));
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

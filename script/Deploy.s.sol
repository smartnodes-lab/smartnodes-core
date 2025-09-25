// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {SmartnodesERC20} from "../src/SmartnodesERC20.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// DAO Configuration
uint256 constant TIMELOCK_DELAY = 2 days;
uint128 constant BASE_UPDATE_TIME = uint128(8 hours);
uint8 constant PROPOSAL_THRESHOLD_PERCENTAGE = 66;

contract Deploy is Script {
    address[] genesis;
    address[] initialActiveNodes;

    function run() external {
        genesis.push(msg.sender);
        genesis.push(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        vm.startBroadcast();

        SmartnodesERC20 token = new SmartnodesERC20(genesis);
        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            msg.sender // Temporary admin to set up roles
        );
        SmartnodesDAO dao = new SmartnodesDAO(token, timelock);
        SmartnodesCore core = new SmartnodesCore(address(token));
        SmartnodesCoordinator coordinator = new SmartnodesCoordinator(
            BASE_UPDATE_TIME,
            PROPOSAL_THRESHOLD_PERCENTAGE,
            address(core),
            address(token),
            initialActiveNodes
        );

        token.setSmartnodes(address(core), address(coordinator));
        token.setDAO(address(timelock));
        core.setCoordinator(address(coordinator));

        // Configure timelock roles
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        bytes32 DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        // Grant DAO the proposer and canceller roles
        timelock.grantRole(PROPOSER_ROLE, address(dao));
        timelock.grantRole(CANCELLER_ROLE, address(dao));
        timelock.grantRole(EXECUTOR_ROLE, address(0));
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);

        bytes32 publicKeyHash = vm.envBytes32("PUBLIC_KEY_HASH");
        core.createValidator(publicKeyHash);
        coordinator.addValidator();

        console.log("Token:", address(token));
        console.log("Timelock:", address(timelock));
        console.log("DAO:", address(dao));
        console.log("Core:", address(core));
        console.log("Coordinator:", address(coordinator));

        vm.stopBroadcast();
    }
}

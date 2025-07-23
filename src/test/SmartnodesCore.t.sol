// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {SmartnodesToken} from "../SmartnodesToken.sol";
import {SmartnodesCore} from "../SmartnodesCore.sol";
import {SmartnodesDeployer} from "./SmartnodesDeployer.sol";

contract SmartnodesTest is Test {
    SmartnodesToken public token;
    SmartnodesCore public core;
    SmartnodesDeployer public deployer;

    // Test addresses
    address public deployerAddr = makeAddr("deployer");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public worker1 = makeAddr("worker1");
    address public worker2 = makeAddr("worker2");
    address[] public genesisNodes;

    // Test constants
    bytes32 constant USER1_PUBKEY = keccak256("user1_pubkey");
    bytes32 constant USER2_PUBKEY = keccak256("user2_pubkey");
    bytes32 constant VALIDATOR1_PUBKEY = keccak256("validator1_pubkey");
    bytes32 constant VALIDATOR2_PUBKEY = keccak256("validator2_pubkey");
    bytes32 constant JOB_ID_1 = keccak256("job1");
    bytes32 constant JOB_ID_2 = keccak256("job2");

    function setUp() public {
        vm.startPrank(deployerAddr);

        // Setup genesis nodes
        genesisNodes.push(validator1);
        genesisNodes.push(validator2);

        // Deploy
        deployer = new SmartnodesDeployer();
        (address tokenAddress, address coreAddress) = deployer
            .deploySmartnodesEcosystem(genesisNodes);

        // Create contract instances
        token = SmartnodesToken(tokenAddress);
        core = SmartnodesCore(coreAddress);

        vm.stopPrank();
    }

    function testAddNetwork() public {
        vm.prank(deployerAddr);
        core.addNetwork("Tensorlink");

        (uint8 networkId, bool exists, string memory name) = core.networks(1);
        assertEq(networkId, 1);
        assertTrue(exists);
        assertEq(name, "Tensorlink");
        assertEq(core.networkCounter(), 1);
    }

    function testAddNetworkMaxLimit() public {
        vm.startPrank(deployerAddr);

        // Add 16 networks (MAX_NETWORKS)
        for (uint8 i = 1; i <= 16; i++) {
            core.addNetwork(string(abi.encodePacked("Network", i)));
        }

        // Try to add 17th network - should revert
        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__InvalidNetworkId.selector
        );
        core.addNetwork("Network17");

        vm.stopPrank();
    }

    function testRemoveNetwork() public {
        vm.startPrank(deployerAddr);
        core.addNetwork("Ethereum");

        // Verify network exists
        (, bool existsBefore, ) = core.networks(1);
        assertTrue(existsBefore);

        // Remove network
        core.removeNetwork(1);

        // Verify network is removed
        (, bool existsAfter, ) = core.networks(1);
        assertFalse(existsAfter);
        vm.stopPrank();
    }

    function testRemoveNonExistentNetwork() public {
        vm.prank(deployerAddr);
        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__InvalidNetworkId.selector
        );
        core.removeNetwork(1);
    }

    // ============= Node Management Tests =============

    function testCreateValidator() public {
        vm.prank(validator1);
        core.createValidator(VALIDATOR1_PUBKEY);

        (bytes32 pubKeyHash, uint8 reputation, bool active, bool exists) = core
            .validators(validator1);
        assertEq(pubKeyHash, VALIDATOR1_PUBKEY);
        assertEq(reputation, 0);
        assertFalse(active);
        assertTrue(exists);
    }

    function testCreateValidatorDuplicate() public {
        vm.startPrank(validator1);
        core.createValidator(VALIDATOR1_PUBKEY);

        vm.expectRevert(SmartnodesCore.SmartnodesCore__NodeExists.selector);
        core.createValidator(VALIDATOR1_PUBKEY);
        vm.stopPrank();
    }

    function testCreateUser() public {
        vm.prank(user1);
        core.createUser(USER1_PUBKEY);

        (bytes32 pubKeyHash, uint8 reputation, bool exists) = core.users(user1);
        assertEq(pubKeyHash, USER1_PUBKEY);
        assertEq(reputation, 1);
        assertTrue(exists);
    }

    function testCreateUserDuplicate() public {
        vm.startPrank(user1);
        core.createUser(USER1_PUBKEY);

        vm.expectRevert(SmartnodesCore.SmartnodesCore__NodeExists.selector);
        core.createUser(USER1_PUBKEY);
        vm.stopPrank();
    }

    // ============= Job Management Tests =============

    function testRequestJobWithETH() public {
        // Setup
        vm.startPrank(deployerAddr);
        core.addNetwork("Tensorlink");
        vm.stopPrank();

        vm.prank(user1);
        core.createUser(USER1_PUBKEY);

        // Fund user1 with ETH
        vm.deal(user1, 10 ether);

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        vm.prank(user1);
        core.requestJob{value: 1 ether}(
            USER1_PUBKEY,
            JOB_ID_1,
            1,
            capacities,
            0
        );

        (
            uint128 payment,
            uint8 networkId,
            uint8 state,
            uint8 paymentType,
            address owner
        ) = core.jobs(JOB_ID_1);
        assertEq(payment, 1 ether);
        assertEq(networkId, 1);
        assertEq(state, 1); // Pending
        assertEq(paymentType, 1); // ETH
        assertEq(owner, user1);
    }

    function testRequestJobWithSNOTokens() public {
        // Setup
        vm.startPrank(deployerAddr);
        core.addNetwork("Tensorlink");
        vm.stopPrank();

        vm.prank(user1);
        core.createUser(USER1_PUBKEY);

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;
        uint128 payment = 1000e18; // 1000 SNO tokens

        vm.prank(user1);
        core.requestJob(USER1_PUBKEY, JOB_ID_1, 1, capacities, payment);

        (
            uint128 jobPayment,
            uint8 networkId,
            uint8 state,
            uint8 paymentType,
            address owner
        ) = core.jobs(JOB_ID_1);
        assertEq(jobPayment, payment);
        assertEq(networkId, 1);
        assertEq(state, 1); // Pending
        assertEq(paymentType, 0); // SNO_TOKEN
        assertEq(owner, user1);
    }
}

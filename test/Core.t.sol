// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseSmartnodesTest} from "./BaseTest.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";

/**
 * @title SmartnodesCoreTest
 * @notice Tests for SmartnodesCore contract functionality
 */
contract SmartnodesCoreTest is BaseSmartnodesTest {
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
        vm.expectRevert(SmartnodesCore.Core__InvalidNetworkId.selector);
        core.addNetwork("Network17");

        vm.stopPrank();
    }

    function testRemoveNetwork() public {
        addTestNetwork("Ethereum");

        // Verify network exists
        (, bool existsBefore, ) = core.networks(1);
        assertTrue(existsBefore);

        // Remove network
        vm.prank(deployerAddr);
        core.removeNetwork(1);

        // Verify network is removed
        (, bool existsAfter, ) = core.networks(1);
        assertFalse(existsAfter);
    }

    function testRemoveNonExistentNetwork() public {
        vm.prank(deployerAddr);
        vm.expectRevert(SmartnodesCore.Core__InvalidNetworkId.selector);
        core.removeNetwork(1);
    }

    // ============= Node Management Tests =============

    function testCreateValidator() public {
        createTestValidator(validator1, VALIDATOR1_PUBKEY);

        (bytes32 pubKeyHash, uint8 reputation, bool locked, bool exists) = core
            .validators(validator1);
        assertEq(pubKeyHash, VALIDATOR1_PUBKEY);
        assertEq(reputation, 0);
        assertTrue(locked);
        assertTrue(exists);
    }

    function testCreateValidatorDuplicate() public {
        createTestValidator(validator1, VALIDATOR1_PUBKEY);

        vm.expectRevert(SmartnodesCore.Core__NodeExists.selector);
        vm.prank(validator1);
        core.createValidator(VALIDATOR1_PUBKEY);
    }

    function testCreateUser() public {
        createTestUser(user1, USER1_PUBKEY);

        (bytes32 pubKeyHash, uint8 reputation, bool locked, bool exists) = core
            .users(user1);
        assertEq(pubKeyHash, USER1_PUBKEY);
        assertEq(reputation, 1);
        assertFalse(locked);
        assertTrue(exists);
    }

    function testCreateUserDuplicate() public {
        createTestUser(user1, USER1_PUBKEY);

        vm.expectRevert(SmartnodesCore.Core__NodeExists.selector);
        vm.prank(user1);
        core.createUser(USER1_PUBKEY);
    }

    // ============= Job Management Tests =============

    function testRequestJobWithETH() public {
        // Setup
        addTestNetwork("Tensorlink");
        createTestUser(user1, USER1_PUBKEY);
        fundUserWithETH(user1, 10 ether);

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        createTestJob(user1, JOB_ID_1, 1, capacities, 1 ether);

        (
            uint128 payment,
            uint8 networkId,
            uint8 state,
            bool payWithSNO,
            address owner
        ) = core.jobs(JOB_ID_1);
        assertEq(payment, 1 ether);
        assertEq(networkId, 1);
        assertEq(state, 1); // Pending
        assertEq(payWithSNO, false); // ETH
        assertEq(owner, user1);
    }

    function testRequestJobWithSNO() public {
        // Setup
        addTestNetwork("Tensorlink");
        createTestUser(user1, USER1_PUBKEY);

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        createTestJob(user1, JOB_ID_1, 1, capacities, 0); // 0 ETH means SNO payment

        (
            uint128 jobPayment,
            uint8 networkId,
            uint8 state,
            bool payWithSNO,
            address owner
        ) = core.jobs(JOB_ID_1);
        assertEq(jobPayment, 1000e18); // Default SNO payment from helper
        assertEq(networkId, 1);
        assertEq(state, 1); // Pending
        assertEq(payWithSNO, true); // SNO_TOKEN
        assertEq(owner, user1);
    }
}

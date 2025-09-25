// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseSmartnodesTest} from "./BaseTest.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";

/**
 * @title SmartnodesCoreTest
 * @notice Tests for SmartnodesCore contract functionality
 */
contract SmartnodesCoreTest is BaseSmartnodesTest {
    // ============= Node Management Tests =============

    function testCreateValidator() public view {
        (bytes32 pubKeyHash, bool locked, bool exists) = core.validators(
            validator1
        );
        assertEq(pubKeyHash, VALIDATOR1_PUBKEY);
        assertTrue(locked);
        assertTrue(exists);
    }

    function testCreateValidatorDuplicate() public {
        vm.expectRevert(SmartnodesCore.Core__NodeExists.selector);
        vm.prank(validator1);
        core.createValidator(VALIDATOR1_PUBKEY);
    }

    function testCreateUser() public {
        createTestUser(user1, USER1_PUBKEY);

        (bytes32 pubKeyHash, bool locked, bool exists) = core.users(user1);
        assertEq(pubKeyHash, USER1_PUBKEY);
        assertTrue(locked);
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
        createTestUser(user1, USER1_PUBKEY);
        fundUserWithETH(user1, 10 ether);

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        createTestJob(user1, JOB_ID_1, capacities, 1 ether);

        // Updated to work with packed Job struct
        (address owner, uint80 payment, uint16 packedData) = core.jobs(
            JOB_ID_1
        );

        // Use helper functions to unpack data
        uint8 state = core.unpackState(packedData);
        bool payWithSNO = core.unpackPayWithSNO(packedData);

        assertEq(payment, 1 ether);
        assertEq(state, 1); // Pending
        assertEq(payWithSNO, false); // ETH
        assertEq(owner, user1);
    }

    function testRequestJobWithSNO() public {
        // Setup
        createTestUser(user1, USER1_PUBKEY);

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        createTestJob(user1, JOB_ID_1, capacities, 0); // 0 ETH means SNO payment

        // Updated to work with packed Job struct
        (address owner, uint80 payment, uint16 packedData) = core.jobs(
            JOB_ID_1
        );

        // Use helper functions to unpack data
        uint8 state = core.unpackState(packedData);
        bool payWithSNO = core.unpackPayWithSNO(packedData);

        assertEq(payment, 1000e18); // Default SNO payment from helper
        assertEq(state, 1); // Pending
        assertEq(payWithSNO, true); // SNO_TOKEN
        assertEq(owner, user1);
    }

    // ============= Additional Helper Tests for Packed Data =============

    function testJobDataPacking() public {
        createTestUser(user1, USER1_PUBKEY);
        fundUserWithETH(user1, 10 ether); // Fund the user with ETH

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        // Test various network IDs, states, and payment types
        createTestJob(user1, JOB_ID_1, capacities, 1 ether);

        (address owner, uint80 payment, uint16 packedData) = core.jobs(
            JOB_ID_1
        );

        assertEq(core.unpackState(packedData), 1); // Pending
        assertEq(core.unpackPayWithSNO(packedData), false); // ETH payment
    }

    function testMaxPaymentAmount() public {
        createTestUser(user1, USER1_PUBKEY);
        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        // Test with maximum uint80 value
        uint80 maxPayment = type(uint80).max;
        fundUserWithETH(user1, maxPayment);

        vm.prank(user1);
        core.requestJob{value: maxPayment}(
            USER1_PUBKEY,
            JOB_ID_1,
            "tensorlink",
            capacities,
            0 // No SNO payment, using ETH
        );

        (address owner, uint80 payment, uint16 packedData) = core.jobs(
            JOB_ID_1
        );
        assertEq(payment, maxPayment);
    }
}

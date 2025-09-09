// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {BaseSmartnodesTest} from "./BaseTest.sol";

/**
 * @title SmartnodesCoordinatorTest
 * @notice Tests for SmartnodesCoordinator contract functionality with merkle tree rewards
 */
contract SmartnodesCoordinatorTest is BaseSmartnodesTest {
    function _setupInitialState() internal override {
        // Coordinator-specific setup
        BaseSmartnodesTest._setupInitialState();

        // Add second validator for testing
        vm.prank(validator2);
        core.createValidator(VALIDATOR2_PUBKEY);
        vm.prank(validator2);
        coordinator.addValidator();

        // Fund the system for testing
        _setupContractFunding();
    }

    function testExecuteProposal1000() public {
        _testExecuteProposal(1000);
    }

    function testExecuteProposal100() public {
        _testExecuteProposal(100);
    }

    function testExecuteProposal10() public {
        _testExecuteProposal(10);
    }

    function testExecuteProposal0() public {
        _testExecuteProposal(0);
    }

    function _testExecuteProposal(uint256 numWorkers) public {
        (uint128 updateTime, ) = coordinator.timeConfig();
        vm.warp(block.timestamp + updateTime * 2);

        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(numWorkers);
        bytes32[] memory leaves = _generateLeaves(participants);
        bytes32 merkleRoot = _buildMerkleTree(leaves);

        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = JOB_ID_1;

        address[] memory workers = new address[](numWorkers);
        uint256[] memory capacities = new uint256[](numWorkers);
        for (uint256 i = 0; i < numWorkers; i++) {
            workers[i] = address(uint160(0x3000 + i));
            capacities[i] = 10e18 + (i * 5e18);
        }

        address[] memory validatorsToRemove = new address[](0);

        bytes32 proposalHash = keccak256(
            abi.encode(
                1,
                merkleRoot,
                validatorsToRemove,
                jobHashes,
                workers,
                capacities
            )
        );

        vm.prank(validator1);
        coordinator.createProposal(proposalHash);

        uint8 proposalId = coordinator.getNumProposals();

        vm.prank(validator1);
        coordinator.voteForProposal(proposalId);

        vm.prank(validator2);
        coordinator.voteForProposal(proposalId);

        uint256 initialDistributionId = token.s_currentDistributionId();
        uint256 initialTotalSupply = token.totalSupply();

        vm.prank(validator1);
        coordinator.executeProposal(
            proposalId,
            merkleRoot,
            totalCapacity,
            validatorsToRemove,
            jobHashes,
            workers,
            capacities
        );

        uint256 newDistributionId = token.s_currentDistributionId();
        assertEq(
            newDistributionId,
            initialDistributionId + 1,
            "New distribution should be created"
        );

        (
            bytes32 storedRoot,
            SmartnodesToken.PaymentAmounts memory workerReward,
            uint256 storedCapacity,
            bool active,
            uint256 timestamp
        ) = token.s_distributions(newDistributionId);

        assertEq(storedRoot, merkleRoot, "Stored merkle root should match");
        assertEq(storedCapacity, totalCapacity, "Stored capacity should match");
        if (numWorkers == 0) {
            assertFalse(active, "Empty distribution should not be active");
        } else {
            assertTrue(active, "Distribution should be active");
        }

        console.log("Merkle distribution created successfully");
        console.log("Distribution ID:", newDistributionId);
        console.log("Worker reward SNO:", workerReward.sno / 1e18);
    }

    function testCreateProposal() public {
        (uint128 updateTime, ) = coordinator.timeConfig();
        vm.warp(block.timestamp + updateTime * 2);

        uint256 numWorkers = 5;
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(numWorkers);

        bytes32[] memory leaves = _generateLeaves(participants);
        bytes32 merkleRoot = _buildMerkleTree(leaves);

        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = JOB_ID_1;

        address[] memory workers = new address[](numWorkers);
        uint256[] memory capacities = new uint256[](numWorkers);
        for (uint256 i = 0; i < numWorkers; i++) {
            workers[i] = address(uint160(0x3000 + i));
            capacities[i] = 10 + (i * 5);
        }

        address[] memory validatorsToRemove = new address[](0);

        bytes32 proposalHash = keccak256(
            abi.encode(
                1,
                merkleRoot,
                validatorsToRemove,
                jobHashes,
                workers,
                capacities
            )
        );

        vm.prank(validator1);
        coordinator.createProposal(proposalHash);

        uint8 proposalId = coordinator.getNumProposals();
        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);

        assertEq(proposal.creator, validator1);
        assertEq(proposal.votes, 0);

        console.log("Proposal created successfully with ID:", proposalId);
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Total capacity:", totalCapacity);
    }

    function testVoteForProposal() public {
        (uint128 updateTime, ) = coordinator.timeConfig();
        vm.warp(block.timestamp + updateTime * 2);

        uint256 numWorkers = 1;
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(numWorkers);
        bytes32 merkleRoot = _buildMerkleTree(_generateLeaves(participants));

        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = JOB_ID_1;

        address[] memory workers = new address[](numWorkers);
        uint256[] memory capacities = new uint256[](numWorkers);
        workers[0] = worker1;
        capacities[0] = 10;

        address[] memory validatorsToRemove = new address[](0);

        bytes32 proposalHash = keccak256(
            abi.encode(
                1,
                merkleRoot,
                validatorsToRemove,
                jobHashes,
                workers,
                capacities
            )
        );

        vm.prank(validator1);
        coordinator.createProposal(proposalHash);

        uint8 proposalId = coordinator.getNumProposals();

        vm.prank(validator2);
        coordinator.voteForProposal(proposalId);

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertEq(proposal.votes, 1);

        console.log("Voting successful. Total votes:", proposal.votes);
    }

    function testCannotVoteTwice() public {
        (uint128 updateTime, ) = coordinator.timeConfig();
        vm.warp(block.timestamp + updateTime * 2);

        uint256 numWorkers = 1;
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(numWorkers);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {BaseSmartnodesTest} from "./BaseTest.sol";

/**
 * @title SmartnodesCoordinatorTest
 * @notice Tests for SmartnodesCoordinator contract functionality
 */
contract SmartnodesCoordinatorTest is BaseSmartnodesTest {
    function _setupInitialState() internal override {
        // Coordinator-specific setup
        addTestNetwork("Tensorlink");
        createTestValidator(validator1, VALIDATOR1_PUBKEY);

        // Add validator to coordinator
        vm.prank(validator1);
        coordinator.addValidator(validator1);
    }

    function testCreateProposal() public {
        (uint128 updateTime, ) = coordinator.timeConfig();
        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint256 proposalId = createBasicProposal(validator1);

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertEq(proposal.creator, validator1);
        assertEq(proposal.votes, 0);
        assertFalse(proposal.executed);
    }

    function testVoteForProposal() public {
        // Setup proposal
        (uint128 updateTime, ) = coordinator.timeConfig();
        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint256 proposalId = createBasicProposal(validator1);

        // Vote for proposal
        vm.prank(validator1);
        coordinator.voteForProposal(proposalId);

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertEq(proposal.votes, 1);
    }

    function testCannotVoteTwice() public {
        // Setup proposal
        (uint128 updateTime, ) = coordinator.timeConfig();
        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint256 proposalId = createBasicProposal(validator1);

        // First vote
        vm.prank(validator1);
        coordinator.voteForProposal(proposalId);

        // Second vote should fail
        vm.expectRevert(
            SmartnodesCoordinator.Coordinator__AlreadyVoted.selector
        );
        vm.prank(validator1);
        coordinator.voteForProposal(proposalId);
    }

    function testExecuteProposalMinimum() public {
        // Setup proposal with enough votes
        (uint128 updateTime, ) = coordinator.timeConfig();
        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint256 proposalId = createBasicProposal(validator1);

        vm.prank(validator1);
        coordinator.voteForProposal(proposalId);

        // Execute proposal
        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = JOB_ID_1;

        address[] memory jobWorkers = new address[](1);
        jobWorkers[0] = worker1;

        uint256[] memory jobCapacities = new uint256[](1);
        jobCapacities[0] = 100;

        address[] memory validatorsToRemove = new address[](0);

        vm.prank(validator1);
        coordinator.executeProposal(
            proposalId,
            validatorsToRemove,
            jobHashes,
            jobWorkers,
            jobCapacities
        );

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertTrue(proposal.executed);
    }

    function testExecuteProposalMaximum() public {
        // Setup
        (uint128 updateTime, ) = coordinator.timeConfig();
        vm.warp(block.timestamp + updateTime + 1);

        bytes32[] memory jobHashes = new bytes32[](50);
        address[] memory jobWorkers = new address[](100);
        uint256[] memory jobCapacities = new uint256[](100);
        address[] memory validatorsToRemove = new address[](0);

        // Prepare 50 job hashes
        for (uint256 i = 0; i < 50; i++) {
            jobHashes[i] = keccak256(abi.encodePacked("job", i));
        }

        // Prepare 100 worker addresses
        for (uint256 i = 0; i < 100; i++) {
            jobWorkers[i] = address(
                uint160(uint256(keccak256(abi.encodePacked("worker", i))))
            );
        }

        // Prepare 100 capacities
        for (uint256 i = 0; i < 100; i++) {
            jobCapacities[i] = 100;
        }

        bytes32 proposalHash = keccak256(
            abi.encode(
                validatorsToRemove,
                jobHashes,
                jobCapacities,
                jobWorkers,
                block.timestamp
            )
        );

        vm.prank(validator1);
        coordinator.createProposal(proposalHash);

        (, uint128 nextProposalId) = coordinator.roundData();
        uint256 proposalId = nextProposalId - 1;

        vm.prank(validator1);
        coordinator.voteForProposal(proposalId);

        // Execute the proposal
        vm.prank(validator1);
        coordinator.executeProposal(
            proposalId,
            validatorsToRemove,
            jobHashes,
            jobWorkers,
            jobCapacities
        );

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertTrue(proposal.executed);
    }

    function testAddValidator() public {
        // Create a new validator in core first
        createTestValidator(validator2, VALIDATOR2_PUBKEY);

        vm.prank(validator2);
        coordinator.addValidator(validator2);

        assertTrue(coordinator.isValidator(validator2));
        assertEq(coordinator.getValidatorCount(), 2); // 1 initial + 1 new
    }

    function testRemoveValidator() public {
        uint256 initialCount = coordinator.getValidatorCount();

        vm.prank(validator1);
        coordinator.removeValidator();

        assertFalse(coordinator.isValidator(validator1));
        assertEq(coordinator.getValidatorCount(), initialCount - 1);
    }
}

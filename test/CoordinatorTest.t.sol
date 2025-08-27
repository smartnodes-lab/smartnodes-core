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
        BaseSmartnodesTest._setupInitialState();
        executeProposalRound();
        addTestNetwork("Tensorlink");
    }

    function testCreateProposal() public {
        (uint128 updateTime, ) = coordinator.timeConfig();

        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint8 proposalId = createBasicProposal(validator1);

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertEq(proposal.creator, validator1);
        assertEq(proposal.votes, 1);
    }

    function testVoteForProposal() public {
        // Setup proposal
        (uint128 updateTime, ) = coordinator.timeConfig();
        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint8 proposalId = createBasicProposal(validator1);

        vm.prank(validator2);
        core.createValidator(VALIDATOR2_PUBKEY);
        coordinator.addValidator(validator2);

        // Vote for proposal
        vm.prank(validator2);
        coordinator.voteForProposal(proposalId);

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(proposalId);
        assertEq(proposal.votes, 2);
    }

    function testCannotVoteTwice() public {
        // Setup proposal
        (uint128 updateTime, ) = coordinator.timeConfig();
        // Fast forward time to expire the round and allow proposal creation
        vm.warp(block.timestamp + updateTime + 1);

        uint8 proposalId = createBasicProposal(validator1);

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

        // Execute proposal
        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = JOB_ID_1;

        address[] memory jobWorkers = new address[](1);
        jobWorkers[0] = worker1;

        uint256[] memory jobCapacities = new uint256[](1);
        jobCapacities[0] = 100;

        address[] memory validatorsToRemove = new address[](0);

        bytes32 proposalHash = keccak256(
            abi.encode(validatorsToRemove, jobHashes, jobCapacities, jobWorkers)
        );

        vm.prank(validator1);
        coordinator.createProposal(proposalHash);

        SmartnodesCoordinator.Proposal memory proposal = coordinator
            .getProposal(1);

        console.log("Proposal creator:", proposal.creator);
        console.log("Proposal votes:", proposal.votes);

        vm.prank(validator1);
        coordinator.executeProposal(
            1,
            validatorsToRemove,
            jobHashes,
            jobWorkers,
            jobCapacities
        );
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
            abi.encode(validatorsToRemove, jobHashes, jobCapacities, jobWorkers)
        );

        vm.prank(validator1);
        coordinator.createProposal(proposalHash);

        uint8 proposalId = 1;

        // Execute the proposal
        vm.prank(validator1);
        coordinator.executeProposal(
            proposalId,
            validatorsToRemove,
            jobHashes,
            jobWorkers,
            jobCapacities
        );
    }

    function testAddValidator() public {
        // Create a new validator in core first
        vm.prank(validator2);
        core.createValidator(VALIDATOR2_PUBKEY);
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

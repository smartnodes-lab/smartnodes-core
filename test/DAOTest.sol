// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseSmartnodesTest} from "./BaseTest.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title DAOTest
 * @notice Test contract for DAO governance functionality
 */
contract DAOTest is BaseSmartnodesTest {
    function setUp() public override {
        super.setUp();

        // Debug: Check token balances after setup
        console.log("Validator1 balance:", token.balanceOf(validator1) / 1e18);
        console.log("Validator2 balance:", token.balanceOf(validator2) / 1e18);
        console.log("User1 balance:", token.balanceOf(user1) / 1e18);
        console.log("Total supply:", token.totalSupply() / 1e18);
        console.log("Quorum required:", dao.quorumRequired() / 1e18);
    }

    /**
     * @notice Test DAO proposal to set validator lock amount
     */
    function testDAOSetValidatorLockAmount() public {
        uint256 newLockAmount = 2_000_000e18; // 2M tokens
        uint256 oldLockAmount = token.s_validatorLockAmount();

        console.log("Old validator lock amount:", oldLockAmount / 1e18);
        console.log("New validator lock amount:", newLockAmount / 1e18);

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Update validator lock amount to 2M SNO"
        );

        uint256 voteAmount = 100_000e18;
        voteOnProposal(proposalId, validator1, voteAmount, true);
        voteOnProposal(proposalId, validator2, voteAmount, true);
        voteOnProposal(proposalId, validator3, voteAmount, true);
        voteOnProposal(proposalId, user1, voteAmount, true);
        voteOnProposal(proposalId, user2, voteAmount, true);

        // Check if we have enough votes for quorum
        (uint256 forVotes, uint256 againstVotes, uint256 totalVotes) = dao
            .getProposalVotes(proposalId);
        uint256 quorumRequired = dao.quorumRequired();
        console.log("For votes:", forVotes);
        console.log("Against votes:", againstVotes);
        console.log("Total votes:", totalVotes);
        console.log("Quorum required:", quorumRequired);

        // Execute proposal
        executeProposal(proposalId);

        // Verify the change
        assertEq(
            token.s_validatorLockAmount(),
            newLockAmount,
            "Validator lock amount not updated"
        );
        console.log("Successfully updated validator lock amount via DAO");
    }

    /**
     * @notice Test DAO proposal to set user lock amount
     */
    function testDAOSetUserLockAmount() public {
        uint256 newLockAmount = 200e18; // 200 tokens
        uint256 oldLockAmount = token.s_userLockAmount();

        console.log("Old user lock amount:", oldLockAmount / 1e18);
        console.log("New user lock amount:", newLockAmount / 1e18);

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setUserLockAmount(uint256)",
            newLockAmount
        );

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Update user lock amount to 200 SNO"
        );

        uint256 voteAmount = 100_000e18;
        voteOnProposal(proposalId, validator1, voteAmount, true);
        voteOnProposal(proposalId, validator2, voteAmount, true);
        voteOnProposal(proposalId, validator3, voteAmount, true);
        voteOnProposal(proposalId, user1, voteAmount, true);
        voteOnProposal(proposalId, user2, voteAmount, true);

        // Execute proposal
        executeProposal(proposalId);

        // Verify the change
        assertEq(
            token.s_userLockAmount(),
            newLockAmount,
            "User lock amount not updated"
        );
        console.log("Successfully updated user lock amount via DAO");
    }

    /**
     * @notice Test DAO proposal to halve distribution interval
     */
    function testDAOHalveDistributionInterval() public {
        uint256 oldInterval = token.s_distributionInterval();
        uint256 expectedNewInterval = oldInterval / 2;

        console.log("Old distribution interval:", oldInterval / 3600, "hours");
        console.log(
            "Expected new interval:",
            expectedNewInterval / 3600,
            "hours"
        );

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("halveDistributionInterval()");

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Halve the distribution interval"
        );

        // Vote on proposal
        uint256 voteAmount = 100_000e18;
        voteOnProposal(proposalId, validator1, voteAmount, true);
        voteOnProposal(proposalId, validator2, voteAmount, true);
        voteOnProposal(proposalId, validator3, voteAmount, true);
        voteOnProposal(proposalId, user1, voteAmount, true);
        voteOnProposal(proposalId, user2, voteAmount, true);

        // Execute proposal
        executeProposal(proposalId);

        // Verify the change
        assertEq(
            token.s_distributionInterval(),
            expectedNewInterval,
            "Distribution interval not halved"
        );
        console.log("Successfully halved distribution interval via DAO");
    }

    /**
     * @notice Test DAO proposal to double distribution interval
     */
    function testDAODoubleDistributionInterval() public {
        uint256 oldInterval = token.s_distributionInterval();
        uint256 expectedNewInterval = oldInterval * 2;

        console.log("Old distribution interval:", oldInterval / 3600, "hours");
        console.log(
            "Expected new interval:",
            expectedNewInterval / 3600,
            "hours"
        );

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("doubleDistributionInterval()");

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Double the distribution interval"
        );

        uint256 voteAmount = 100_000e18;
        voteOnProposal(proposalId, validator1, voteAmount, true);
        voteOnProposal(proposalId, validator2, voteAmount, true);
        voteOnProposal(proposalId, validator3, voteAmount, true);
        voteOnProposal(proposalId, user1, voteAmount, true);
        voteOnProposal(proposalId, user2, voteAmount, true);

        // Wait for voting to end
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        // Verify proposal succeeded before queueing
        SmartnodesDAO.ProposalState currentState = dao.state(proposalId);
        console.log("Proposal state after voting:", uint8(currentState));
        assertEq(
            uint8(currentState),
            uint8(SmartnodesDAO.ProposalState.Succeeded),
            "Proposal should have succeeded"
        );

        // Queue the proposal
        dao.queue(proposalId);

        // Wait for timelock delay (2 days)
        vm.warp(block.timestamp + dao.TIMELOCK_DELAY());

        // Execute the proposal
        dao.execute(proposalId);

        // Verify the change
        assertEq(
            token.s_distributionInterval(),
            expectedNewInterval,
            "Distribution interval not doubled"
        );
        console.log("Successfully doubled distribution interval via DAO");
    }

    /**
     * @notice Test DAO proposal failure due to insufficient votes
     */
    function testDAOProposalFailsWithInsufficientVotes() public {
        uint256 newLockAmount = 500_000e18;

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "This proposal should fail"
        );

        // Vote with only a small amount (insufficient for quorum)
        // With 5% quorum on ~6.5M total supply, we need ~325k votes minimum
        // 10 votes = 100 tokens, way below quorum
        voteOnProposal(proposalId, validator1, 10, true);

        // Wait for voting period to end
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        // Check state - should be defeated due to insufficient quorum
        SmartnodesDAO.ProposalState currentState = dao.state(proposalId);
        assertEq(
            uint8(currentState),
            uint8(SmartnodesDAO.ProposalState.Defeated),
            "Proposal should be defeated due to insufficient quorum"
        );

        // Try to queue (should fail)
        vm.expectRevert("SmartnodesDAO__ProposalDidNotPass()");
        dao.queue(proposalId);

        console.log("Proposal correctly failed due to insufficient quorum");
    }

    /**
     * @notice Test DAO proposal failure when against votes exceed for votes
     */
    function testDAOProposalFailsWhenRejected() public {
        uint256 newLockAmount = 500_000e18;

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "This proposal should be rejected"
        );

        // Vote against the proposal with sufficient votes for quorum but more against than for
        uint256 voteAmount = 400; // This should provide enough total votes for quorum
        voteOnProposal(proposalId, validator1, voteAmount, false); // Against
        voteOnProposal(proposalId, validator2, voteAmount, false); // Against
        voteOnProposal(proposalId, validator3, voteAmount, false); // Against
        voteOnProposal(proposalId, user1, voteAmount, true); // For
        voteOnProposal(proposalId, user2, voteAmount, true); // For

        // Total: 1200 against, 800 for = 2000 total votes (should meet quorum)

        // Wait for voting period to end
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        // Check state - should be defeated because against > for
        SmartnodesDAO.ProposalState currentState = dao.state(proposalId);
        assertEq(
            uint8(currentState),
            uint8(SmartnodesDAO.ProposalState.Defeated),
            "Proposal should be defeated due to more against votes"
        );

        // Try to queue (should fail)
        vm.expectRevert("SmartnodesDAO__ProposalDidNotPass()");
        dao.queue(proposalId);

        console.log(
            "Proposal correctly failed due to more against votes than for votes"
        );
    }

    /**
     * @notice Test refund mechanism after voting
     */
    function testRefundMechanism() public {
        uint256 newLockAmount = 500_000e18;

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Test refund mechanism"
        );

        // Record initial balances
        uint256 validator1BalanceBefore = token.balanceOf(validator1);
        uint256 user1BalanceBefore = token.balanceOf(user1);

        // Vote on proposal
        uint256 votes = 100;
        uint256 expectedCost = votes * votes; // 10,000 tokens

        voteOnProposal(proposalId, validator1, votes, true);
        voteOnProposal(proposalId, user1, votes, false);

        // Wait for voting period to end
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        // Claim refunds
        vm.prank(validator1);
        dao.claimRefund(proposalId);

        vm.prank(user1);
        dao.claimRefund(proposalId);

        // Check balances are restored
        assertEq(
            token.balanceOf(validator1),
            validator1BalanceBefore,
            "Validator1 tokens not fully refunded"
        );
        assertEq(
            token.balanceOf(user1),
            user1BalanceBefore,
            "User1 tokens not fully refunded"
        );

        console.log("Refund mechanism working correctly");
    }

    /**
     * @notice Test multiple proposals can exist simultaneously
     */
    function testMultipleProposals() public {
        // Create first proposal
        address[] memory targets1 = new address[](1);
        targets1[0] = address(token);
        bytes[] memory calldatas1 = new bytes[](1);
        calldatas1[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            2_000_000e18
        );

        vm.prank(validator1);
        uint256 proposalId1 = createDAOProposal(
            targets1,
            calldatas1,
            "Proposal 1"
        );

        // Create second proposal
        address[] memory targets2 = new address[](1);
        targets2[0] = address(token);
        bytes[] memory calldatas2 = new bytes[](1);
        calldatas2[0] = abi.encodeWithSignature(
            "setUserLockAmount(uint256)",
            200e18
        );

        vm.prank(validator2);
        uint256 proposalId2 = createDAOProposal(
            targets2,
            calldatas2,
            "Proposal 2"
        );

        // Vote on both proposals
        voteOnProposal(proposalId1, validator1, 300, true);
        voteOnProposal(proposalId1, user1, 300, true);
        voteOnProposal(proposalId1, user2, 300, true);

        voteOnProposal(proposalId2, validator2, 300, true);
        voteOnProposal(proposalId2, validator3, 300, true);
        voteOnProposal(proposalId2, user1, 300, false); // Vote against second proposal

        // Check both proposals exist and have correct states
        assertEq(
            uint8(dao.state(proposalId1)),
            uint8(SmartnodesDAO.ProposalState.Active)
        );
        assertEq(
            uint8(dao.state(proposalId2)),
            uint8(SmartnodesDAO.ProposalState.Active)
        );

        console.log("Multiple proposals created and voted on successfully");
    }
}

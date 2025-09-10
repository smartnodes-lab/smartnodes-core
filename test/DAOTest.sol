// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseSmartnodesTest} from "./BaseTest.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title DAOTest
 * @notice Test contract for DAO governance functionality
 */
contract DAOTest is BaseSmartnodesTest {
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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Update validator lock amount to 2M SNO"
        );

        uint256 amount = 700;
        voteOnProposal(proposalId, validator1, amount, true);
        voteOnProposal(proposalId, validator2, amount, true);
        voteOnProposal(proposalId, validator3, amount, true);
        voteOnProposal(proposalId, user1, amount, true);
        voteOnProposal(proposalId, user2, 700, true);

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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Update user lock amount to 200 SNO"
        );

        uint256 amount = 700;
        voteOnProposal(proposalId, validator1, amount, true);
        voteOnProposal(proposalId, validator2, amount, true);
        voteOnProposal(proposalId, validator3, amount, true);
        voteOnProposal(proposalId, user1, amount, true);
        voteOnProposal(proposalId, user2, 700, true);

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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Halve the distribution interval"
        );

        // Vote on proposal
        uint256 amount = 700;
        voteOnProposal(proposalId, validator1, amount, true);
        voteOnProposal(proposalId, validator2, amount, true);
        voteOnProposal(proposalId, validator3, amount, true);
        voteOnProposal(proposalId, user1, amount, true);
        voteOnProposal(proposalId, user2, 700, true);

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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Double the distribution interval"
        );

        uint256 amount = 700;
        voteOnProposal(proposalId, validator1, amount, true);
        voteOnProposal(proposalId, validator2, amount, true);
        voteOnProposal(proposalId, validator3, amount, true);
        voteOnProposal(proposalId, user1, amount, true);
        voteOnProposal(proposalId, user2, 700, true);

        // Execute proposal
        executeProposal(proposalId);

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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "This proposal should fail"
        );

        // Vote with only a small amount (insufficient for quorum)
        voteOnProposal(proposalId, validator1, 10, true); // Only 10 votes = 100 tokens

        // Try to execute (should fail due to insufficient quorum)
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        vm.expectRevert("quorum not reached");
        dao.execute(proposalId);

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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "This proposal should be rejected"
        );

        // Vote against the proposal with sufficient votes
        uint256 amount = 700;
        voteOnProposal(proposalId, validator1, amount, false);
        voteOnProposal(proposalId, validator2, amount, false);
        voteOnProposal(proposalId, validator3, amount, false);
        voteOnProposal(proposalId, user1, amount, true);
        voteOnProposal(proposalId, user2, 700, true);

        // Try to execute (should fail because against > for)
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        vm.expectRevert("proposal did not pass");
        dao.execute(proposalId);

        console.log(
            "Proposal correctly failed due to more against votes than for votes"
        );
    }

    /**
     * @notice Test quadratic voting mechanics
     */
    function testQuadraticVotingMechanics() public {
        uint256 newLockAmount = 500_000e18;

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Test quadratic voting"
        );

        // Check balances before voting
        uint256 balanceBefore = token.balanceOf(validator1);
        console.log("Validator1 balance before voting:", balanceBefore / 1e18);

        // Vote with 50 votes (should cost 50^2 = 2500 tokens)
        uint256 votes = 50;
        uint256 expectedCost = votes * votes; // 2500 tokens

        voteOnProposal(proposalId, validator1, votes, true);

        // Check balance after voting
        uint256 balanceAfter = token.balanceOf(validator1);
        console.log("Validator1 balance after voting:", balanceAfter / 1e18);
        console.log("Tokens locked for voting:", expectedCost / 1e18);

        // Verify the quadratic cost
        assertEq(
            balanceBefore - balanceAfter,
            expectedCost,
            "Incorrect quadratic voting cost"
        );

        // Check that votes were recorded correctly
        (uint256 recordedVotes, uint256 lockedTokens) = dao.getVotesOf(
            proposalId,
            validator1
        );
        assertEq(recordedVotes, votes, "Votes not recorded correctly");
        assertEq(
            lockedTokens,
            expectedCost,
            "Locked tokens not recorded correctly"
        );

        console.log("Quadratic voting mechanics working correctly");
    }

    /**
     * @notice Test refund mechanism after proposal ends
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

        uint256 proposalId = createDAOProposal(
            targets,
            calldatas,
            "Test refund mechanism"
        );

        uint256 balanceBefore = token.balanceOf(validator1);
        uint256 votes = 30;
        uint256 expectedCost = votes * votes; // 900 tokens

        // Vote on proposal
        voteOnProposal(proposalId, validator1, votes, true);

        uint256 balanceAfterVoting = token.balanceOf(validator1);
        assertEq(
            balanceBefore - balanceAfterVoting,
            expectedCost,
            "Incorrect voting cost"
        );

        // Wait for voting period to end
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        // Claim refund
        vm.prank(validator1);
        dao.claimRefund(proposalId);

        uint256 balanceAfterRefund = token.balanceOf(validator1);

        // Should have original balance back
        assertEq(
            balanceAfterRefund,
            balanceBefore,
            "Refund not processed correctly"
        );

        console.log("Refund mechanism working correctly");
    }

    /**
     * @notice Test multiple proposals with different outcomes
     */
    function testMultipleProposals() public {
        console.log("Testing multiple DAO proposals...");

        // Proposal 1: Set validator lock amount (should pass)
        address[] memory targets1 = new address[](1);
        targets1[0] = address(token);
        bytes[] memory calldatas1 = new bytes[](1);
        calldatas1[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            1_500_000e18
        );

        uint256 proposalId1 = createDAOProposal(
            targets1,
            calldatas1,
            "Proposal 1: Update validator lock"
        );

        // Proposal 2: Set user lock amount (should pass)
        address[] memory targets2 = new address[](1);
        targets2[0] = address(token);
        bytes[] memory calldatas2 = new bytes[](1);
        calldatas2[0] = abi.encodeWithSignature(
            "setUserLockAmount(uint256)",
            150e18
        );

        uint256 proposalId2 = createDAOProposal(
            targets2,
            calldatas2,
            "Proposal 2: Update user lock"
        );

        // Vote on both proposals
        uint256 amount = 700;
        voteOnProposal(proposalId1, validator1, amount, true);
        voteOnProposal(proposalId1, validator2, amount, true);
        voteOnProposal(proposalId1, validator3, amount, true);
        voteOnProposal(proposalId1, user1, amount, true);
        voteOnProposal(proposalId1, user2, amount, true);
        voteOnProposal(proposalId2, validator1, amount, true);
        voteOnProposal(proposalId2, validator2, amount, true);
        voteOnProposal(proposalId2, validator3, amount, true);
        voteOnProposal(proposalId2, user1, amount, true);
        voteOnProposal(proposalId2, user2, amount, true);

        // Execute both proposals
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);

        dao.execute(proposalId1);
        dao.execute(proposalId2);

        // Verify both changes
        assertEq(
            token.s_validatorLockAmount(),
            1_500_000e18,
            "Proposal 1 failed"
        );
        assertEq(token.s_userLockAmount(), 150e18, "Proposal 2 failed");

        console.log("Multiple proposals executed successfully");
    }

    /**
     * @notice Helper function to log proposal state
     */
    function _logProposalState(uint256 proposalId) internal view {
        (
            uint256 id,
            address proposer,
            address[] memory targets,
            bytes[] memory calldatas,
            string memory description,
            uint256 startTime,
            uint256 endTime,
            uint256 forVotes,
            uint256 againstVotes,
            bool executed,
            bool canceled
        ) = abi.decode(
                abi.encode(dao.getProposal(proposalId)),
                (
                    uint256,
                    address,
                    address[],
                    bytes[],
                    string,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    bool,
                    bool
                )
            );

        console.log("Proposal ID:", id);
        console.log("For votes:", forVotes);
        console.log("Against votes:", againstVotes);
        console.log("Executed:", executed);
        console.log("Canceled:", canceled);
    }
}

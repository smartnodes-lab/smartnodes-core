// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Test.sol";
import {BaseSmartnodesTest} from "./BaseTest.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";

contract SmartnodesDAOTest is BaseSmartnodesTest {
    address public owner = makeAddr("owner");

    uint256 constant MIN_VOTING_POWER = 1000e18;
    uint256 constant VOTING_PERIOD = 7 days;

    // function testProposeAddNetwork() public {
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     assertEq(proposalId, 1);
    //     assertEq(dao.proposalCounter(), 1);

    //     // Check proposal details
    //     SmartnodesDAO.Proposal memory proposal = dao.getProposal(proposalId);
    //     assertEq(proposal.id, proposalId);
    //     assertEq(proposal.proposer, user1);
    //     assertEq(
    //         uint8(proposal.proposalType),
    //         uint8(SmartnodesDAO.ProposalType.ADD_NETWORK)
    //     );
    //     assertEq(
    //         uint8(proposal.status),
    //         uint8(SmartnodesDAO.ProposalStatus.Active)
    //     );
    //     assertEq(proposal.startTime, block.timestamp);
    //     assertEq(proposal.endTime, block.timestamp + VOTING_PERIOD);
    // }

    // function testProposeAddNetworkInsufficientVotingPower() public {
    //     // Give user1 insufficient voting power
    //     // token.setUnclaimedRewards(user1, MIN_VOTING_POWER - 1);

    //     vm.prank(user1);
    //     vm.expectRevert(SmartnodesDAO.DAO__InsufficientVotingPower.selector);
    //     dao.proposeAddNetwork("Ethereum", "Add Ethereum network support");
    // }

    // function testProposeRemoveNetwork() public {
    //     // Give user1 sufficient voting power
    //     // token.setUnclaimedRewards(user1, MIN_VOTING_POWER);

    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeRemoveNetwork(1, "Remove network 1");

    //     assertEq(proposalId, 1);

    //     SmartnodesDAO.Proposal memory proposal = dao.getProposal(proposalId);
    //     assertEq(
    //         uint8(proposal.proposalType),
    //         uint8(SmartnodesDAO.ProposalType.REMOVE_NETWORK)
    //     );
    // }

    // function testCastVote() public {
    //     // Setup: Create a proposal
    //     // token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Setup voting power for user2
    //     uint256 votingPower = 5000e18;
    //     // token.setUnclaimedRewards(user2, votingPower);

    //     // Cast vote
    //     vm.prank(user2);
    //     dao.castVote(proposalId, true);

    //     // Check vote recorded
    //     SmartnodesDAO.Vote memory vote = dao.getVote(proposalId, user2);
    //     assertTrue(vote.hasVoted);
    //     assertTrue(vote.support);
    //     assertEq(vote.votingPower, votingPower);

    //     // Check proposal vote counts
    //     SmartnodesDAO.Proposal memory proposal = dao.getProposal(proposalId);
    //     assertEq(proposal.forVotes, votingPower);
    //     assertEq(proposal.againstVotes, 0);
    // }

    // function testCastVoteAgainst() public {
    //     // Setup: Create a proposal
    //     // token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Setup voting power for user2
    //     uint256 votingPower = 3000e18;
    //     token.setUnclaimedRewards(user2, votingPower);

    //     // Cast vote against
    //     vm.prank(user2);
    //     dao.castVote(proposalId, false);

    //     // Check proposal vote counts
    //     SmartnodesDAO.Proposal memory proposal = dao.getProposal(proposalId);
    //     assertEq(proposal.forVotes, 0);
    //     assertEq(proposal.againstVotes, votingPower);
    // }

    // function testCastVoteAlreadyVoted() public {
    //     // Setup: Create a proposal and cast initial vote
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     token.setUnclaimedRewards(user2, 2000e18);
    //     vm.prank(user2);
    //     dao.castVote(proposalId, true);

    //     // Try to vote again
    //     vm.prank(user2);
    //     vm.expectRevert(SmartnodesDAO.DAO__AlreadyVoted.selector);
    //     dao.castVote(proposalId, false);
    // }

    // function testCastVoteInsufficientVotingPower() public {
    //     // Setup: Create a proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Try to vote with no voting power
    //     vm.prank(user2);
    //     vm.expectRevert(SmartnodesDAO.DAO__InsufficientVotingPower.selector);
    //     dao.castVote(proposalId, true);
    // }

    // function testCastVoteProposalNotActive() public {
    //     // Setup: Create a proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Fast forward past voting period
    //     vm.warp(block.timestamp + VOTING_PERIOD + 1);

    //     token.setUnclaimedRewards(user2, 2000e18);
    //     vm.prank(user2);
    //     vm.expectRevert(SmartnodesDAO.DAO__ProposalNotActive.selector);
    //     dao.castVote(proposalId, true);
    // }

    // function testExecuteProposalSuccess() public {
    //     // Setup total unclaimed rewards
    //     uint256 totalUnclaimed = 100000e18;
    //     token.setTotalTokensUnclaimed(totalUnclaimed);

    //     // Create proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Cast enough votes to pass (need 10% quorum and 51% majority)
    //     uint256 quorumAmount = (totalUnclaimed * 10) / 100; // 10% quorum
    //     uint256 majorityVotes = (quorumAmount * 51) / 100 + 1; // 51% of quorum + 1

    //     token.setUnclaimedRewards(user2, majorityVotes);
    //     vm.prank(user2);
    //     dao.castVote(proposalId, true);

    //     // Fast forward past voting period
    //     vm.warp(block.timestamp + VOTING_PERIOD + 1);

    //     // Execute proposal
    //     dao.executeProposal(proposalId);

    //     // Check execution
    //     assertTrue(core.addNetworkCalled());
    //     assertEq(core.lastNetworkAdded(), "Ethereum");

    //     SmartnodesDAO.Proposal memory proposal = dao.getProposal(proposalId);
    //     assertTrue(proposal.executed);
    //     assertEq(
    //         uint8(proposal.status),
    //         uint8(SmartnodesDAO.ProposalStatus.Executed)
    //     );
    // }

    // function testExecuteProposalFailedQuorum() public {
    //     // Setup total unclaimed rewards
    //     uint256 totalUnclaimed = 100000e18;
    //     token.setTotalTokensUnclaimed(totalUnclaimed);

    //     // Create proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Cast insufficient votes (below 10% quorum)
    //     uint256 insufficientVotes = (totalUnclaimed * 5) / 100; // Only 5%
    //     token.setUnclaimedRewards(user2, insufficientVotes);
    //     vm.prank(user2);
    //     dao.castVote(proposalId, true);

    //     // Fast forward past voting period
    //     vm.warp(block.timestamp + VOTING_PERIOD + 1);

    //     // Try to execute proposal
    //     vm.expectRevert(SmartnodesDAO.DAO__ProposalNotPassed.selector);
    //     dao.executeProposal(proposalId);
    // }

    // function testExecuteProposalFailedMajority() public {
    //     // Setup total unclaimed rewards
    //     uint256 totalUnclaimed = 100000e18;
    //     token.setTotalTokensUnclaimed(totalUnclaimed);

    //     // Create proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Cast votes that meet quorum but fail majority (more against than for)
    //     uint256 quorumAmount = (totalUnclaimed * 15) / 100; // 15% quorum
    //     uint256 forVotes = (quorumAmount * 40) / 100; // 40% for
    //     uint256 againstVotes = (quorumAmount * 60) / 100; // 60% against

    //     token.setUnclaimedRewards(user2, forVotes);
    //     token.setUnclaimedRewards(user3, againstVotes);

    //     vm.prank(user2);
    //     dao.castVote(proposalId, true);

    //     vm.prank(user3);
    //     dao.castVote(proposalId, false);

    //     // Fast forward past voting period
    //     vm.warp(block.timestamp + VOTING_PERIOD + 1);

    //     // Try to execute proposal
    //     vm.expectRevert(SmartnodesDAO.DAO__ProposalNotPassed.selector);
    //     dao.executeProposal(proposalId);
    // }

    // function testCancelProposal() public {
    //     // Create proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Cancel proposal as owner
    //     vm.prank(owner);
    //     dao.cancelProposal(proposalId);

    //     SmartnodesDAO.Proposal memory proposal = dao.getProposal(proposalId);
    //     assertEq(
    //         uint8(proposal.status),
    //         uint8(SmartnodesDAO.ProposalStatus.Cancelled)
    //     );
    // }

    // function testCancelProposalNotOwner() public {
    //     // Create proposal
    //     token.setUnclaimedRewards(user1, MIN_VOTING_POWER);
    //     vm.prank(user1);
    //     uint256 proposalId = dao.proposeAddNetwork(
    //         "Ethereum",
    //         "Add Ethereum network support"
    //     );

    //     // Try to cancel as non-owner
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     dao.cancelProposal(proposalId);
    // }
}

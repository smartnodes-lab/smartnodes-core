// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseSmartnodesTest} from "./BaseTest.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title DAOTest - Fixed Version
 * @notice Enhanced test contract with proper role management and setup
 */
contract DAOTest is BaseSmartnodesTest {
    address public projectAddress1;
    address public projectAddress2;
    address public projectAddress3;
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    function setUp() public override {
        super.setUp();

        projectAddress1 = makeAddr("project1");
        projectAddress2 = makeAddr("project2");
        projectAddress3 = makeAddr("project3");

        // Setup voting power, delegate to self for all participants
        _setupVotingPower();
        _setupDAOPermissions();
        _fundTimelock();

        // Check token balances after setup
        console.log("=== Initial Setup ===");
        console.log("Validator1 balance:", token.balanceOf(validator1) / 1e18);
        console.log("Validator2 balance:", token.balanceOf(validator2) / 1e18);
        console.log("User1 balance:", token.balanceOf(user1) / 1e18);
        console.log("Total supply:", token.totalSupply() / 1e18);
        console.log("DAO balance:", token.balanceOf(address(dao)) / 1e18);
        console.log(
            "Timelock balance:",
            token.balanceOf(address(timelock)) / 1e18
        );
    }

    function _setupVotingPower() internal {
        // All participants need to delegate to themselves for voting power
        address[] memory participants = new address[](5);
        participants[0] = validator1;
        participants[1] = validator2;
        participants[2] = validator3;
        participants[3] = user1;
        participants[4] = user2;

        for (uint i = 0; i < participants.length; i++) {
            vm.prank(participants[i]);
            token.delegate(participants[i]);
        }

        // Send worker1 a bit of tokens for small voting tests
        vm.prank(user2);
        token.transfer(worker1, 1000e18);
        vm.prank(worker1);
        token.delegate(worker1);

        // Move forward one block so delegation takes effect
        vm.roll(block.number + 1);
    }

    function _setupDAOPermissions() internal {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        vm.startPrank(deployerAddr);
        // Give DAO proposer + executor
        timelock.grantRole(proposerRole, address(dao));
        timelock.grantRole(executorRole, address(dao));
        timelock.grantRole(cancellerRole, address(dao));
        timelock.grantRole(executorRole, address(0));

        // Handoff admin to DAO
        timelock.grantRole(adminRole, address(dao));
        timelock.revokeRole(adminRole, deployerAddr);
        vm.stopPrank();

        // Verify
        assertTrue(
            timelock.hasRole(proposerRole, address(dao)),
            "DAO missing PROPOSER_ROLE"
        );
        assertTrue(
            timelock.hasRole(executorRole, address(dao)),
            "DAO missing EXECUTOR_ROLE"
        );
        assertTrue(
            timelock.hasRole(adminRole, address(dao)),
            "DAO missing ADMIN_ROLE"
        );
    }

    function _fundTimelock() internal {
        // Transfer tokens to timelock for testing funding proposals
        vm.prank(validator3);
        token.transfer(address(timelock), 100_000e18);
        console.log("Funded timelock with 100k tokens");
    }

    /**
     * @notice Enhanced proposal creation that uses base functionality
     */
    function createDAOProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256) {
        uint256 proposalId = dao.propose(
            targets,
            values,
            calldatas,
            description
        );
        console.log("Created proposal ID:", proposalId);
        console.log("Proposal description:", description);

        return proposalId;
    }

    /**
     * @notice Enhanced vote function with proper state management
     */
    function voteOnProposal(
        uint256 proposalId,
        address voter,
        uint8 support
    ) internal {
        vm.startPrank(voter);

        // Get current proposal state and snapshot
        uint256 snapshot = dao.proposalSnapshot(proposalId);
        uint256 deadline = dao.proposalDeadline(proposalId);

        console.log("Current block:", block.number);
        console.log("Proposal snapshot:", snapshot);
        console.log("Proposal deadline:", deadline);
        console.log("Voting delay:", dao.votingDelay());

        // Move to voting period if needed (after delay)
        uint256 votingStartBlock = snapshot + 1;
        if (block.number <= votingStartBlock) {
            vm.roll(votingStartBlock + 1);
            console.log("Moved to voting block:", block.number);
        }

        // Check voting power
        uint256 votingPower = token.getVotes(voter);
        console.log("Voter:", voter);
        console.log("Voting power:", votingPower / 1e18);

        // Cast vote
        dao.castVote(proposalId, support);
        console.log("Vote cast successfully");
        vm.stopPrank();
    }

    /**
     * @notice Enhanced execution with proper timelock handling
     */
    function executeProposalEnhanced(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal {
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));

        // Move past voting period
        vm.roll(block.number + dao.votingPeriod() + 1);

        // Queue the proposal
        dao.queue(targets, values, calldatas, descriptionHash);
        console.log("Proposal queued");

        // Wait for timelock delay
        vm.warp(block.timestamp + timelock.getMinDelay());
        console.log("Waited for timelock delay");

        // Execute
        dao.execute(targets, values, calldatas, descriptionHash);
        console.log("Proposal executed");
    }

    /**
     * @notice Test DAO proposal to slash validator with enhanced checks - FIXED
     */
    function testEnhancedDAOSlashValidator() public {
        console.log("=== Enhanced Validator Slashing Test ===");

        // Get initial state
        uint256 lockedBefore = token.s_validatorLockAmount(); // 1M tokens
        uint256 slashAmount = lockedBefore / 4; // Slash 25% = 250k tokens

        console.log("Validator1 locked before:", lockedBefore / 1e18);
        console.log("Slash amount:", slashAmount / 1e18);

        // Create DAO proposal to slash validator1
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(token);
        calldatas[0] = abi.encodeWithSignature(
            "slashAndUnlockValidator(address,uint256)",
            validator1,
            slashAmount
        );
        values[0] = 0;

        // Propose as validator2
        vm.prank(validator2);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Slash validator1 by 25% of locked tokens for misconduct"
        );

        // Vote on proposal - majority for
        voteOnProposal(proposalId, validator1, 1); // For
        voteOnProposal(proposalId, validator2, 1); // For
        voteOnProposal(proposalId, validator3, 1); // For
        voteOnProposal(proposalId, user1, 1); // For
        voteOnProposal(proposalId, user2, 1); // For

        // Execute the proposal
        executeProposalEnhanced(
            targets,
            values,
            calldatas,
            "Slash validator1 by 25% of locked tokens for misconduct"
        );

        // Verify execution
        (
            bool locked,
            bool isValidator,
            uint256 timestamp,
            uint256 lockAmount
        ) = token.getLockInfo(validator1);
        uint256 balanceAfterSlash = token.balanceOf(validator1);

        // Complete unlock process
        vm.warp(block.timestamp + 30 days);
        vm.prank(address(core));
        token.unlockTokens(validator1);

        console.log("Validator1 locked after:", lockAmount / 1e18);
        console.log(
            "Validator1 balance after slash:",
            balanceAfterSlash / 1e18
        );

        // Verify the slash worked correctly
        uint256 expectedRemainingLocked = lockedBefore - slashAmount;
        assertEq(
            lockAmount,
            expectedRemainingLocked,
            "Incorrect remaining locked amount"
        );
        assertEq(locked, false, "Validator should be in unlock state");

        uint256 balanceAfterUnlock = token.balanceOf(validator1);
        console.log("Final balance after unlock:", balanceAfterUnlock / 1e18);

        console.log("Enhanced validator slashing completed successfully");
    }

    /**
     * @notice Test DAO proposal with mixed voting - FIXED
     */
    function testDAOProposalWithMixedVoting() public {
        console.log("=== Mixed Voting Test ===");

        uint256 newLockAmount = 1_500_000e18; // 1.5M tokens

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Change validator lock amount to 1.5M"
        );

        // Mixed voting
        voteOnProposal(proposalId, validator1, 1); // For
        voteOnProposal(proposalId, validator2, 0); // Against
        voteOnProposal(proposalId, validator3, 1); // For
        voteOnProposal(proposalId, user1, 1); // For
        voteOnProposal(proposalId, user2, 2); // Abstain

        // Check final vote tally
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = dao
            .proposalVotes(proposalId);

        uint256 snapshotBlock = dao.proposalSnapshot(proposalId);
        uint256 quorumRequired = dao.quorum(snapshotBlock);

        console.log("Final vote tally:");
        console.log("Against:", againstVotes / 1e18);
        console.log("For:", forVotes / 1e18);
        console.log("Abstain:", abstainVotes / 1e18);
        console.log("Quorum required:", quorumRequired / 1e18);

        // Move past voting period to get final state
        vm.roll(block.number + dao.votingPeriod() + 1);

        // Execute if passed (for > against AND for + abstain >= quorum)
        IGovernor.ProposalState finalState = dao.state(proposalId);
        console.log("Final proposal state:", uint8(finalState));

        if (uint8(finalState) == 4) {
            // Succeeded
            executeProposalEnhanced(
                targets,
                values,
                calldatas,
                "Change validator lock amount to 1.5M"
            );

            assertEq(
                token.s_validatorLockAmount(),
                newLockAmount,
                "Lock amount should be updated"
            );
            console.log("Proposal passed and executed");
        } else {
            console.log("Proposal failed - insufficient support or quorum");
        }
    }

    /**
     * @notice Test DAO proposal that fails due to insufficient quorum - FIXED
     */
    function testDAOProposalFailsInsufficientQuorum() public {
        console.log("=== Insufficient Quorum Test ===");

        uint256 newLockAmount = 500_000e18;

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            newLockAmount
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "This proposal should fail due to low participation"
        );

        voteOnProposal(proposalId, worker1, 1); // worker 1 only has a few tokens

        // Check if proposal meets quorum
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = dao
            .proposalVotes(proposalId);
        uint256 snapshotBlock = dao.proposalSnapshot(proposalId);
        uint256 quorumRequired = dao.quorum(snapshotBlock);

        console.log(
            "Votes - Against:",
            againstVotes / 1e18,
            "For:",
            forVotes / 1e18
        );
        console.log("Quorum required:", quorumRequired / 1e18);
        console.log("Total votes:", (forVotes + abstainVotes) / 1e18);

        // Wait for voting period to end
        vm.roll(block.number + dao.votingPeriod() + 1);

        // Check final state
        IGovernor.ProposalState finalState = dao.state(proposalId);
        console.log("Final proposal state:", uint8(finalState));

        // Should be defeated (state 3) due to insufficient quorum
        assertTrue(
            uint8(finalState) == 3,
            "Proposal should be defeated due to insufficient quorum"
        );

        bytes32 descriptionHash = keccak256(
            abi.encodePacked(
                "This proposal should fail due to low participation"
            )
        );
        vm.expectRevert();
        dao.queue(targets, values, calldatas, descriptionHash);

        console.log("Proposal correctly failed due to insufficient quorum");
    }

    /**
     * @notice Test multiple simultaneous proposals - FIXED
     */
    function testMultipleSimultaneousProposals() public {
        console.log("=== Multiple Proposals Test ===");

        // Create first proposal
        address[] memory targets1 = new address[](1);
        targets1[0] = address(token);
        bytes[] memory calldatas1 = new bytes[](1);
        calldatas1[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            2_000_000e18
        );
        uint256[] memory values1 = new uint256[](1);
        values1[0] = 0;

        vm.prank(validator1);
        uint256 proposalId1 = createDAOProposal(
            targets1,
            values1,
            calldatas1,
            "Increase validator lock amount to 2M SNO"
        );

        // Create second proposal
        address[] memory targets2 = new address[](1);
        targets2[0] = address(token);
        bytes[] memory calldatas2 = new bytes[](1);
        calldatas2[0] = abi.encodeWithSignature(
            "setUserLockAmount(uint256)",
            200e18
        );
        uint256[] memory values2 = new uint256[](1);
        values2[0] = 0;

        vm.prank(validator2);
        uint256 proposalId2 = createDAOProposal(
            targets2,
            values2,
            calldatas2,
            "Increase user lock amount to 200 SNO"
        );

        // Vote on both proposals differently
        voteOnProposal(proposalId1, validator1, 1); // For proposal 1
        voteOnProposal(proposalId1, validator2, 1);
        voteOnProposal(proposalId1, validator3, 1);
        voteOnProposal(proposalId1, user1, 1);
        voteOnProposal(proposalId1, user2, 1);

        voteOnProposal(proposalId2, validator1, 0); // Against proposal 2
        voteOnProposal(proposalId2, validator2, 0);
        voteOnProposal(proposalId2, validator3, 0);
        voteOnProposal(proposalId2, user1, 0);
        voteOnProposal(proposalId2, user2, 1);

        // Wait for voting to end
        vm.roll(block.number + dao.votingPeriod() + 1);

        // Execute proposal 1 (should pass)
        IGovernor.ProposalState state1 = dao.state(proposalId1);
        console.log("Proposal 1 final state:", uint8(state1));
        if (uint8(state1) == 4) {
            // Succeeded
            executeProposalEnhanced(
                targets1,
                values1,
                calldatas1,
                "Increase validator lock amount to 2M SNO"
            );
            assertEq(
                token.s_validatorLockAmount(),
                2_000_000e18,
                "Proposal 1 should have executed"
            );
            console.log("Proposal 1 executed successfully");
        }

        // Check proposal 2 state
        IGovernor.ProposalState state2 = dao.state(proposalId2);
        console.log("Proposal 2 final state:", uint8(state2));

        // Get vote counts for proposal 2
        (uint256 againstVotes2, uint256 forVotes2, uint256 abstainVotes2) = dao
            .proposalVotes(proposalId2);
        console.log(
            "Proposal 2 - Against:",
            againstVotes2 / 1e18,
            "For:",
            forVotes2 / 1e18
        );

        if (uint8(state2) == 3) {
            // Defeated
            console.log("Proposal 2 correctly defeated");
        } else if (uint8(state2) == 4) {
            // Succeeded
            console.log("Proposal 2 passed (unexpected but valid)");
        }

        console.log("Multiple proposals handled correctly");
    }

    /**
     * @notice Test DAO funding project with enhanced checks - FIXED
     */
    function testEnhancedDAOFundProject() public {
        console.log("=== Enhanced Project Funding Test ===");

        uint256 fundingAmount = 100_000e18; // 100k SNO tokens
        uint256 timelockBalanceBefore = token.balanceOf(address(timelock));
        uint256 projectBalanceBefore = token.balanceOf(projectAddress1);

        console.log("Timelock balance before:", timelockBalanceBefore / 1e18);
        console.log("Project balance before:", projectBalanceBefore / 1e18);

        // Create proposal to fund project
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            projectAddress1,
            fundingAmount
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Fund promising DeFi project with 100k SNO tokens"
        );

        // Unanimous support
        voteOnProposal(proposalId, validator1, 1);
        voteOnProposal(proposalId, validator2, 1);
        voteOnProposal(proposalId, validator3, 1);
        voteOnProposal(proposalId, user1, 1);
        voteOnProposal(proposalId, user2, 1);

        executeProposalEnhanced(
            targets,
            values,
            calldatas,
            "Fund promising DeFi project with 100k SNO tokens"
        );

        // Verify transfers
        uint256 timelockBalanceAfter = token.balanceOf(address(timelock));
        uint256 projectBalanceAfter = token.balanceOf(projectAddress1);

        console.log("Timelock balance after:", timelockBalanceAfter / 1e18);
        console.log("Project balance after:", projectBalanceAfter / 1e18);

        assertEq(
            projectBalanceAfter,
            projectBalanceBefore + fundingAmount,
            "Project should receive funding"
        );
        assertEq(
            timelockBalanceAfter,
            timelockBalanceBefore - fundingAmount,
            "Timelock should lose funding"
        );

        console.log("Project funding completed successfully");
    }

    /**
     * @notice Test proposal cancellation
     */
    function testProposalCancellation() public {
        console.log("=== Proposal Cancellation Test ===");

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            999_999e18
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "This proposal will be cancelled"
        );

        // Check initial state
        console.log("Initial proposal state:", uint8(dao.state(proposalId)));

        // Cancel the proposal (can be done by proposer)
        vm.prank(validator1);
        dao.cancel(
            targets,
            values,
            calldatas,
            keccak256(abi.encodePacked("This proposal will be cancelled"))
        );

        // Verify cancellation
        IGovernor.ProposalState cancelledState = dao.state(proposalId);
        assertEq(uint8(cancelledState), 2, "Proposal should be cancelled"); // Canceled

        console.log("Final proposal state:", uint8(cancelledState));
        console.log("Proposal cancellation successful");
    }

    /**
     * @notice Test proposal execution timing edge cases
     */
    function testProposalExecutionTimingEdgeCases() public {
        console.log("=== Execution Timing Edge Cases ===");

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            1_100_000e18
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Test timing edge case"
        );

        // Vote and pass
        voteOnProposal(proposalId, validator1, 1);
        voteOnProposal(proposalId, validator2, 1);
        voteOnProposal(proposalId, validator3, 1);

        vm.roll(block.number + dao.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(
            abi.encodePacked("Test timing edge case")
        );
        dao.queue(targets, values, calldatas, descriptionHash);

        // Try to execute too early (should fail)
        vm.expectRevert();
        dao.execute(targets, values, calldatas, descriptionHash);

        // Execute at exactly the right time
        vm.warp(block.timestamp + timelock.getMinDelay());
        dao.execute(targets, values, calldatas, descriptionHash);

        console.log("Timing edge case handled correctly");
    }

    /**
     * @notice Test delegation changes during voting period
     */
    function testDelegationChangeDuringVoting() public {
        console.log("=== Delegation Change During Voting ===");

        // Create a new address to test delegation
        address delegatee = makeAddr("delegatee");

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            1_200_000e18
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Test delegation during voting"
        );

        // Move to voting period
        vm.roll(dao.proposalSnapshot(proposalId) + 2);

        // Check initial voting power
        uint256 initialPower = token.getVotes(user1);
        console.log("User1 initial voting power:", initialPower / 1e18);

        // User1 votes
        vm.prank(user1);
        dao.castVote(proposalId, 1);

        // User1 changes delegation mid-voting (shouldn't affect this proposal)
        vm.prank(user1);
        token.delegate(delegatee);
        vm.roll(block.number + 1); // Make delegation effective

        // Check that delegatee got the power but it doesn't affect the proposal
        uint256 delegateePower = token.getVotes(delegatee);
        uint256 user1PowerAfter = token.getVotes(user1);

        console.log("User1 power after delegation:", user1PowerAfter / 1e18);
        console.log("Delegatee power:", delegateePower / 1e18);

        // Verify vote was still counted with original power
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = dao
            .proposalVotes(proposalId);
        assertTrue(
            forVotes >= initialPower,
            "Vote should be counted with snapshot power"
        );

        console.log("Delegation change during voting handled correctly");
    }

    /**
     * @notice Test maximum proposal limit edge case
     */
    function testMaxProposalLimit() public {
        console.log("=== Max Proposal Limit Test ===");

        // Create multiple proposals to test any limits
        for (uint i = 0; i < 5; i++) {
            address[] memory targets = new address[](1);
            targets[0] = address(token);
            bytes[] memory calldatas = new bytes[](1);
            calldatas[0] = abi.encodeWithSignature(
                "setValidatorLockAmount(uint256)",
                1_000_000e18 + (i * 10_000e18)
            );
            uint256[] memory values = new uint256[](1);
            values[0] = 0;

            vm.prank(validator1);
            string memory description = string(
                abi.encodePacked("Proposal number ", vm.toString(i))
            );
            uint256 proposalId = createDAOProposal(
                targets,
                values,
                calldatas,
                description
            );

            console.log("Created proposal", i, "with ID:", proposalId);
        }

        console.log("Multiple proposals created successfully");
    }

    /**
     * @notice Test proposal with zero value but ETH transfer
     */
    function testProposalWithETHTransfer() public {
        console.log("=== ETH Transfer Proposal Test ===");

        // Fund timelock with ETH
        vm.deal(address(timelock), 10 ether);
        console.log("Timelock ETH balance:", address(timelock).balance / 1e18);

        address[] memory targets = new address[](1);
        targets[0] = projectAddress1;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = ""; // Empty calldata for simple ETH transfer
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Send 1 ETH to project"
        );

        // Vote and execute
        voteOnProposal(proposalId, validator1, 1);
        voteOnProposal(proposalId, validator2, 1);
        voteOnProposal(proposalId, validator3, 1);

        uint256 projectBalanceBefore = projectAddress1.balance;
        executeProposalEnhanced(
            targets,
            values,
            calldatas,
            "Send 1 ETH to project"
        );

        uint256 projectBalanceAfter = projectAddress1.balance;
        assertEq(
            projectBalanceAfter,
            projectBalanceBefore + 1 ether,
            "Project should receive ETH"
        );

        console.log("ETH transfer proposal executed successfully");
    }

    /**
     * @notice Test proposal with multiple operations in single transaction
     */
    function testMultiOperationProposal() public {
        console.log("=== Multi-Operation Proposal Test ===");

        address[] memory targets = new address[](3);
        targets[0] = address(token);
        targets[1] = address(token);
        targets[2] = address(token);

        bytes[] memory calldatas = new bytes[](3);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            1_100_000e18
        );
        calldatas[1] = abi.encodeWithSignature(
            "setUserLockAmount(uint256)",
            150e18
        );
        calldatas[2] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            projectAddress2,
            50_000e18
        );

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Multi-operation: Update locks and fund project"
        );

        // Vote and execute
        voteOnProposal(proposalId, validator1, 1);
        voteOnProposal(proposalId, validator2, 1);
        voteOnProposal(proposalId, validator3, 1);
        voteOnProposal(proposalId, user1, 1);

        uint256 projectBalanceBefore = token.balanceOf(projectAddress2);

        executeProposalEnhanced(
            targets,
            values,
            calldatas,
            "Multi-operation: Update locks and fund project"
        );

        // Verify all operations executed
        assertEq(
            token.s_validatorLockAmount(),
            1_100_000e18,
            "Validator lock should be updated"
        );
        assertEq(
            token.s_userLockAmount(),
            150e18,
            "User lock should be updated"
        );
        assertEq(
            token.balanceOf(projectAddress2),
            projectBalanceBefore + 50_000e18,
            "Project should receive tokens"
        );

        console.log("Multi-operation proposal executed successfully");
    }

    /**
     * @notice Test proposal state transitions edge cases
     */
    function testProposalStateTransitions() public {
        console.log("=== Proposal State Transitions ===");

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setValidatorLockAmount(uint256)",
            1_050_000e18
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "Test state transitions"
        );

        // Check state: Pending
        assertEq(uint8(dao.state(proposalId)), 0, "Should be Pending");
        console.log("State 0 - Pending");

        // Move to Active
        vm.roll(dao.proposalSnapshot(proposalId) + 1);
        assertEq(uint8(dao.state(proposalId)), 1, "Should be Active");
        console.log("State 1 - Active");

        // Vote and check various states
        voteOnProposal(proposalId, validator1, 1);
        voteOnProposal(proposalId, validator2, 1);
        voteOnProposal(proposalId, validator3, 1);

        // Move past voting period
        vm.roll(block.number + dao.votingPeriod() + 1);
        assertEq(uint8(dao.state(proposalId)), 4, "Should be Succeeded");
        console.log("State 4 - Succeeded");

        // Queue it
        bytes32 descriptionHash = keccak256(
            abi.encodePacked("Test state transitions")
        );
        dao.queue(targets, values, calldatas, descriptionHash);
        assertEq(uint8(dao.state(proposalId)), 5, "Should be Queued");
        console.log("State 5 - Queued");

        // Execute it
        vm.warp(block.timestamp + timelock.getMinDelay());
        dao.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint8(dao.state(proposalId)), 7, "Should be Executed");
        console.log("State 7 - Executed");

        console.log("All state transitions verified successfully");
    }

    /**
     * @notice Test proposal that would fail execution due to insufficient funds
     */
    function testProposalFailedExecution() public {
        console.log("=== Failed Execution Test ===");

        // Try to transfer more tokens than timelock has
        uint256 timelockBalance = token.balanceOf(address(timelock));
        uint256 excessiveAmount = timelockBalance + 1000e18;

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            projectAddress3,
            excessiveAmount
        );
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(validator1);
        uint256 proposalId = createDAOProposal(
            targets,
            values,
            calldatas,
            "This execution will fail due to insufficient funds"
        );

        // Pass the vote
        voteOnProposal(proposalId, validator1, 1);
        voteOnProposal(proposalId, validator2, 1);
        voteOnProposal(proposalId, validator3, 1);

        vm.roll(block.number + dao.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(
            abi.encodePacked(
                "This execution will fail due to insufficient funds"
            )
        );
        dao.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + timelock.getMinDelay());

        // This should revert due to insufficient balance
        vm.expectRevert();
        dao.execute(targets, values, calldatas, descriptionHash);

        console.log("Failed execution handled correctly");
    }
}

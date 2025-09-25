// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Test.sol";
import {SmartnodesERC20} from "../src/SmartnodesERC20.sol";
import {BaseSmartnodesTest} from "./BaseTest.sol";

/**
 * @title SmartnodesTokenTest
 * @notice Comprehensive tests for SmartnodesERC20 contract functionality
 */
contract SmartnodesTokenTest is BaseSmartnodesTest {
    function _setupInitialState() internal override {
        // Token-specific setup
        BaseSmartnodesTest._setupInitialState();
        createTestUser(user1, USER1_PUBKEY);
    }

    // ============= Token Locking Tests =============

    function testLockValidatorTokens() public {
        // Use validator2 who isn't locked yet
        uint256 initialBalance = token.balanceOf(validator2);

        vm.prank(address(core));
        token.lockTokens(validator2, true);

        // Check validator tokens are locked
        assertEq(
            token.balanceOf(validator2),
            initialBalance - VALIDATOR_LOCK_AMOUNT
        );
    }

    function testLockUserTokens() public {
        // First give user2 enough tokens
        vm.prank(validator1);
        token.transfer(user2, USER_LOCK_AMOUNT);

        uint256 initialUserBalance = token.balanceOf(user2);
        uint256 initialContractBalance = token.balanceOf(address(token));

        vm.prank(address(core));
        token.lockTokens(user2, false);

        // Check user tokens are locked
        assertEq(token.balanceOf(user2), initialUserBalance - USER_LOCK_AMOUNT);
        assertEq(
            token.balanceOf(address(token)),
            initialContractBalance + USER_LOCK_AMOUNT
        );
    }

    function testCannotLockInsufficientTokens() public {
        assertEq(token.balanceOf(user3), 0, "user3 should start with 0 tokens");

        // User 3 doesnt have any tokens, should revert
        vm.expectRevert(SmartnodesERC20.Token__InsufficientBalance.selector);
        vm.prank(address(core));
        token.lockTokens(user3, false);
    }

    function testCannotLockAlreadyLockedTokens() public {
        vm.startPrank(address(core));
        vm.expectRevert(SmartnodesERC20.Token__AlreadyLocked.selector);
        token.lockTokens(user1, true);
        vm.stopPrank();
    }

    function testCannotLockFromNonCore() public {
        vm.expectRevert(SmartnodesERC20.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.lockTokens(validator2, true);
    }

    // ============= Token Unlocking Tests =============

    function testInitiateUnlock() public {
        // validator1 is already locked from setup, so we can directly test unlock
        uint256 initialContractBalance = token.balanceOf(address(token));

        // Initiate unlock
        vm.prank(address(core));
        token.unlockTokens(validator1);

        // Tokens should still be in contract but unlock initiated
        assertEq(token.balanceOf(address(token)), initialContractBalance);
    }

    function testCompleteUnlock() public {
        uint256 initialBalance = token.balanceOf(validator1);
        uint256 initialContractBalance = token.balanceOf(address(token));

        // Initiate unlock
        vm.prank(address(core));
        token.unlockTokens(validator1);

        // Fast forward past unlock period
        vm.warp(block.timestamp + UNLOCK_PERIOD + 1);

        // Complete unlock
        vm.prank(address(core));
        token.unlockTokens(validator1);

        // Check tokens are returned - validator1 should have gained back the locked amount
        assertEq(
            token.balanceOf(validator1),
            initialBalance + VALIDATOR_LOCK_AMOUNT
        );
        // Contract should have less tokens now
        assertEq(
            token.balanceOf(address(token)),
            initialContractBalance - VALIDATOR_LOCK_AMOUNT
        );
    }

    function testCannotUnlockBeforePeriod() public {
        // validator1 is already locked, initiate unlock
        vm.startPrank(address(core));
        token.unlockTokens(validator1);

        // Try to complete unlock before period
        vm.expectRevert(SmartnodesERC20.Token__UnlockPending.selector);
        token.unlockTokens(validator1);
        vm.stopPrank();
    }

    function testCannotUnlockNeverLocked() public {
        vm.prank(address(core));
        vm.expectRevert(SmartnodesERC20.Token__NotLocked.selector);
        token.unlockTokens(user3);
    }

    // ============= Payment Escrow Tests =============

    function testEscrowPayment() public {
        uint256 paymentAmount = 1000e18;

        // Give user1 tokens
        vm.prank(validator1);
        token.transfer(user1, paymentAmount);

        uint256 initialUserBalance = token.balanceOf(user1);
        uint256 initialContractBalance = token.balanceOf(address(token));

        vm.prank(address(core));
        token.escrowPayment(user1, paymentAmount);

        assertEq(token.balanceOf(user1), initialUserBalance - paymentAmount);
        assertEq(
            token.balanceOf(address(token)),
            initialContractBalance + paymentAmount
        );

        SmartnodesERC20.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(user1);
        assertEq(escrowed.sno, paymentAmount);
    }

    function testEscrowEthPayment() public {
        uint256 paymentAmount = 1 ether;
        vm.deal(address(core), paymentAmount);

        vm.prank(address(core));
        token.escrowEthPayment{value: paymentAmount}(user1, paymentAmount);

        SmartnodesERC20.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(user1);
        assertEq(escrowed.eth, paymentAmount);
        assertEq(address(token).balance, paymentAmount);
    }

    function testReleaseEscrowedPayment() public {
        uint256 paymentAmount = 1000e18;

        // Setup escrow
        vm.prank(validator1);
        token.transfer(user1, paymentAmount);

        vm.prank(address(core));
        token.escrowPayment(user1, paymentAmount);

        // Release escrow
        vm.prank(address(core));
        token.releaseEscrowedPayment(user1, paymentAmount);

        SmartnodesERC20.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(user1);
        assertEq(escrowed.sno, 0);
    }

    function testReleaseEscrowedEthPayment() public {
        uint256 paymentAmount = 1 ether;
        vm.deal(address(core), paymentAmount);

        // Setup ETH escrow
        vm.prank(address(core));
        token.escrowEthPayment{value: paymentAmount}(user1, paymentAmount);

        // Release ETH escrow
        vm.prank(address(core));
        token.releaseEscrowedEthPayment(user1, paymentAmount);

        SmartnodesERC20.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(user1);
        assertEq(escrowed.eth, 0);
        assertEq(address(token).balance, paymentAmount); // ETH stays in contract
    }

    // ============= Reward Distribution Tests =============

    /**
     * @notice Test merkle tree generation and distribution creation
     */
    function testMerkleDistributionCreation() public {
        console.log("=== Testing Merkle Distribution Creation ===");

        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(5, false);

        (
            uint256 distributionId,
            bytes32 merkleRoot
        ) = _createAndValidateDistribution(participants, totalCapacity);
        _validateRewardCalculations(distributionId);

        console.log("Merkle distribution creation test passed!");
    }

    /**
     * @notice Test worker reward claiming
     */
    function testWorkerRewardClaiming() public {
        console.log("=== Testing Worker Reward Claiming ===");

        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(100, false);
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        _testWorkerClaiming(distributionId, participants);

        console.log("Worker reward claiming test passed!");
    }

    /**
     * @notice Test the complete end-to-end flow
     */
    function testCompleteRewardFlow() public {
        console.log("=== Testing Complete Reward Flow ===");

        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(1, false);
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        _validateRewardCalculations(distributionId);
        _testWorkerClaiming(distributionId, participants);
        _validateFinalState();

        console.log("Complete reward flow test passed!");
    }

    /**
     * @notice Test reward calculations with different parameters
     */
    function testRewardCalculationAccuracy() public {
        console.log("=== Testing Reward Calculation Accuracy ===");

        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(1, false);
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        // Get stored reward amounts
        (, SmartnodesERC20.PaymentAmounts memory workerReward, , , ) = token
            .s_distributions(distributionId);

        // Calculate expected totals
        uint256 totalSnoReward = INITIAL_EMISSION_RATE + ADDITIONAL_SNO_PAYMENT;
        uint256 totalEthReward = ADDITIONAL_ETH_PAYMENT;

        console.log("Reward calculation accuracy test passed!");
    }

    // ============= Emission Rate Tests =============
    function testEmissionRateAfterOneYear() public {
        // Fast forward one year
        vm.warp(block.timestamp + REWARD_PERIOD);

        uint256 expectedRate = (INITIAL_EMISSION_RATE * 3) / 5;
        assertEq(token.getEmissionRate(), expectedRate);
    }

    function testEmissionRateAfterMultipleYears() public {
        // Fast forward two years
        vm.warp(block.timestamp + (REWARD_PERIOD * 2));

        uint256 expectedRate = (INITIAL_EMISSION_RATE * 3 * 3) / (5 * 5);
        assertEq(token.getEmissionRate(), expectedRate);
    }

    function testTailEmission() public {
        // Fast forward many years to reach tail emission
        vm.warp(block.timestamp + (REWARD_PERIOD * 20));

        assertEq(token.getEmissionRate(), TAIL_EMISSION);
    }

    // ============= Access Control Tests =============

    function testOnlyCoreCanCallProtectedFunctions() public {
        vm.expectRevert(SmartnodesERC20.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.lockTokens(validator2, true);

        vm.expectRevert(SmartnodesERC20.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.unlockTokens(validator1);

        vm.expectRevert(SmartnodesERC20.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.escrowPayment(user1, 1000e18);
    }

    /**
     * @notice Create and validate a merkle distribution
     * @param participants Array of participants
     * @param totalCapacity Total capacity of all participants
     * @return distributionId The created distribution ID
     * @return merkleRoot The merkle root for the distribution
     */
    function _createAndValidateDistribution(
        Participant[] memory participants,
        uint256 totalCapacity
    ) internal returns (uint256 distributionId, bytes32 merkleRoot) {
        // Generate merkle tree
        distributionId = token.s_currentDistributionId() + 1;

        bytes32[] memory leaves = _generateLeaves(participants, distributionId);
        merkleRoot = _buildMerkleTree(leaves);

        console.log("Generated", leaves.length, "leaves");
        console.log("Merkle root:", vm.toString(merkleRoot));

        // Create distribution
        SmartnodesERC20.PaymentAmounts
            memory additionalPayments = SmartnodesERC20.PaymentAmounts({
                sno: uint128(ADDITIONAL_SNO_PAYMENT),
                eth: uint128(ADDITIONAL_ETH_PAYMENT)
            });

        uint256 initialTotalSupply = token.totalSupply();
        uint256 initialContractEth = address(token).balance;

        address[] memory validators = new address[](2);
        validators[0] = address(validator1);
        validators[1] = address(validator2);

        console.log("Initial token supply:", initialTotalSupply / 1e18);
        console.log("Initial contract ETH:", initialContractEth / 1e18);

        vm.prank(address(core));
        token.createMerkleDistribution(
            merkleRoot,
            totalCapacity,
            validators,
            additionalPayments,
            address(validator1)
        );

        distributionId = token.s_currentDistributionId();

        // Validate distribution storage
        (
            bytes32 storedRoot,
            SmartnodesERC20.PaymentAmounts memory workerReward,
            uint256 storedCapacity,
            uint256 timestamp,
            uint256 _distributionId
        ) = token.s_distributions(distributionId);

        assertEq(storedRoot, merkleRoot, "Stored merkle root mismatch");
        assertEq(storedCapacity, totalCapacity, "Stored capacity mismatch");
        console.log("Distribution created and validated successfully");
    }

    /**
     * @notice Validate expected reward calculations
     * @param distributionId The distribution to validate
     */
    function _validateRewardCalculations(uint256 distributionId) internal view {
        (, SmartnodesERC20.PaymentAmounts memory workerReward, , , ) = token
            .s_distributions(distributionId);

        uint256 totalSnoReward = INITIAL_EMISSION_RATE + ADDITIONAL_SNO_PAYMENT;
        uint256 totalEthReward = ADDITIONAL_ETH_PAYMENT;

        uint256 expectedValidatorSno = (totalSnoReward *
            VALIDATOR_REWARD_PERCENTAGE) / 100;
        uint256 expectedValidatorEth = (totalEthReward *
            VALIDATOR_REWARD_PERCENTAGE) / 100;
        uint256 expectedDaoSno = (totalSnoReward * DAO_REWARD_PERCENTAGE) / 100;
        uint256 expectedDaoEth = (totalEthReward * DAO_REWARD_PERCENTAGE) / 100;
        uint256 expectedWorkerSno = totalSnoReward -
            expectedValidatorSno -
            expectedDaoSno;
        uint256 expectedWorkerEth = totalEthReward -
            expectedValidatorEth -
            expectedDaoEth;

        assertEq(
            workerReward.sno,
            expectedWorkerSno,
            "Worker SNO reward mismatch"
        );
        assertEq(
            workerReward.eth,
            expectedWorkerEth,
            "Worker ETH reward mismatch"
        );

        console.log(
            "Expected validator SNO reward:",
            expectedValidatorSno / 1e18
        );
        console.log("Expected worker SNO reward:", expectedWorkerSno / 1e18);
    }

    /**
     * @notice Test worker claiming process
     * @param distributionId The distribution ID
     * @param participants Array of participants
     */
    function _testWorkerClaiming(
        uint256 distributionId,
        Participant[] memory participants
    ) internal {
        uint256 numWorkers = participants.length;
        bytes32[] memory leaves = _generateLeaves(participants, distributionId);

        // Calculate total rewards
        uint256 totalSnoReward = INITIAL_EMISSION_RATE + ADDITIONAL_SNO_PAYMENT;
        uint256 totalEthReward = ADDITIONAL_ETH_PAYMENT;

        uint256 expectedValidatorSno = (totalSnoReward *
            VALIDATOR_REWARD_PERCENTAGE) / 100;
        uint256 expectedValidatorEth = (totalEthReward *
            VALIDATOR_REWARD_PERCENTAGE) / 100;
        uint256 expectedDaoSno = (totalSnoReward * DAO_REWARD_PERCENTAGE) / 100;
        uint256 expectedDaoEth = (totalEthReward * DAO_REWARD_PERCENTAGE) / 100;
        uint256 expectedWorkerSno = totalSnoReward -
            expectedValidatorSno -
            expectedDaoSno;
        uint256 expectedWorkerEth = totalEthReward -
            expectedValidatorEth -
            expectedDaoEth;

        uint256 totalCapacity = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            totalCapacity += participants[i].capacity;
        }

        for (uint256 i = 0; i < numWorkers; i++) {
            address worker = participants[i].addr;
            uint256 workerCapacity = participants[i].capacity;

            console.log(
                "Testing claim for worker",
                i,
                "with capacity",
                workerCapacity
            );

            // Generate proof
            bytes32[] memory proof = _generateMerkleProof(leaves, i);

            // Record pre-claim state
            uint256 preClaimBalance = token.balanceOf(worker);
            uint256 preClaimEth = worker.balance;

            // Claim rewards
            vm.prank(worker);
            token.claimMerkleRewards(distributionId, workerCapacity, proof);

            // Expected worker rewards
            uint256 expectedWorkerSnoShare = (expectedWorkerSno *
                workerCapacity) / totalCapacity;
            uint256 expectedWorkerEthShare = (expectedWorkerEth *
                workerCapacity) / totalCapacity;

            uint256 postClaimBalance = token.balanceOf(worker);
            uint256 postClaimEth = worker.balance;

            assertEq(
                postClaimBalance - preClaimBalance,
                expectedWorkerSnoShare,
                "Worker SNO reward incorrect"
            );
            assertEq(
                postClaimEth - preClaimEth,
                expectedWorkerEthShare,
                "Worker ETH reward incorrect"
            );
            assertTrue(
                token.s_claimed(distributionId, worker),
                "Worker claim should be marked as completed"
            );
        }

        console.log("All worker claims successful");
    }

    function testClaim9999thWorker() public {
        console.log("=== Testing claim for a specific worker ===");

        _setupContractFunding();

        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(10_000, false);

        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        // the 10,000th worker (index 9999)
        uint256 workerIndex = 9_999;
        Participant memory worker = participants[workerIndex];

        // Generate Merkle proof just for this worker
        bytes32[] memory leaves = _generateLeaves(participants, distributionId);
        bytes32[] memory proof = _generateMerkleProof(leaves, workerIndex);

        // Pre-claim balances
        uint256 preClaimBalance = token.balanceOf(worker.addr);

        // Claim rewards
        vm.prank(worker.addr);
        token.claimMerkleRewards(distributionId, worker.capacity, proof);

        uint256 validatorSnoReward = ((INITIAL_EMISSION_RATE +
            ADDITIONAL_SNO_PAYMENT) * VALIDATOR_REWARD_PERCENTAGE) / 100;

        uint256 daoSnoReward = ((INITIAL_EMISSION_RATE +
            ADDITIONAL_SNO_PAYMENT) * DAO_REWARD_PERCENTAGE) / 100;

        uint256 expectedWorkerSno = (INITIAL_EMISSION_RATE +
            ADDITIONAL_SNO_PAYMENT) -
            validatorSnoReward -
            daoSnoReward;

        uint256 expectedWorkerSnoShare = (expectedWorkerSno * worker.capacity) /
            totalCapacity;

        assertEq(
            token.balanceOf(worker.addr) - preClaimBalance,
            expectedWorkerSnoShare,
            "Worker SNO reward incorrect"
        );

        assertTrue(
            token.s_claimed(distributionId, worker.addr),
            "Worker claim should be marked as completed"
        );

        console.log("Specific worker claim test passed!");
    }

    /**
     * @notice Test creating multiple distributions in a loop and claiming rewards
     */
    function testMultipleMerkleDistributions() public {
        _setupContractFunding();
        vm.deal(address(core), ADDITIONAL_ETH_PAYMENT * 350);
        vm.prank(address(core));
        (bool success, ) = address(token).call{
            value: ADDITIONAL_ETH_PAYMENT * 350
        }("");
        require(success, "Multi-distribution funding failed");

        uint256 numDistributions = 100;
        Participant[][] memory allParticipants = new Participant[][](
            numDistributions
        );
        uint256[] memory distributionIds = new uint256[](numDistributions);

        // Create multiple distributions
        for (uint256 i = 0; i < numDistributions; i++) {
            (
                Participant[] memory participants,
                uint256 totalCapacity
            ) = _setupTestParticipants(5, false);
            vm.warp(block.timestamp + UPDATE_TIME);
            (uint256 distributionId, ) = _createAndValidateDistribution(
                participants,
                totalCapacity
            );
            distributionIds[i] = distributionId;
            allParticipants[i] = participants;
        }

        // Prepare batch claim arrays
        uint256[] memory capacities = new uint256[](numDistributions);
        bytes32[][] memory proofs = new bytes32[][](numDistributions);

        for (uint256 i = 0; i < numDistributions; i++) {
            Participant memory worker = allParticipants[i][0]; // pick first worker for simplicity
            capacities[i] = worker.capacity;

            bytes32[] memory leaves = _generateLeaves(
                allParticipants[i],
                distributionIds[i]
            );
            proofs[i] = _generateMerkleProof(leaves, 0);
        }

        // Perform batch claim
        vm.prank(allParticipants[0][0].addr);
        token.batchClaimMerkleRewards(distributionIds, capacities, proofs);

        // Verify claims
        for (uint256 i = 0; i < numDistributions; i++) {
            Participant memory worker = allParticipants[i][0];
            assertTrue(
                token.s_claimed(distributionIds[i], worker.addr),
                "Worker claim not recorded"
            );
        }

        console.log("Batch claim test passed!");
    }

    // ============= Additional Edge Case Tests =============

    function testLockTokensWithExactBalance() public {
        // Test locking when user has exactly the required amount
        vm.prank(validator1);
        token.transfer(worker1, USER_LOCK_AMOUNT);

        vm.prank(address(core));
        token.lockTokens(worker1, false);

        assertEq(token.balanceOf(worker1), 0);
    }

    function testLockTokensJustUnderRequiredAmount() public {
        // Test with 1 wei less than required
        vm.prank(validator1);
        token.transfer(worker1, USER_LOCK_AMOUNT - 1);

        vm.expectRevert(SmartnodesERC20.Token__InsufficientBalance.selector);
        vm.prank(address(core));
        token.lockTokens(worker1, false);
    }

    // ============= Token Unlocking Edge Cases =============

    function testUnlockAtExactTimeBoundary() public {
        vm.prank(address(core));
        token.unlockTokens(validator1);

        // Fast forward to exactly the unlock time
        vm.warp(block.timestamp + UNLOCK_PERIOD - 1);

        // Should still revert as we need > unlock period
        vm.expectRevert(SmartnodesERC20.Token__UnlockPending.selector);
        vm.prank(address(core));
        token.unlockTokens(validator1);
    }

    function testUnlockOneSecondAfterBoundary() public {
        vm.prank(address(core));
        token.unlockTokens(validator1);

        vm.warp(block.timestamp + UNLOCK_PERIOD + 1);

        // Should succeed now
        vm.prank(address(core));
        token.unlockTokens(validator1);
    }

    function testMultipleUnlockInitiations() public {
        vm.startPrank(address(core));
        token.unlockTokens(validator1);

        // Try to initiate unlock again - should revert
        vm.expectRevert(SmartnodesERC20.Token__UnlockPending.selector);
        token.unlockTokens(validator1);
        vm.stopPrank();
    }

    // ============= Escrow Edge Cases =============

    function testEscrowZeroAmount() public {
        vm.expectRevert(); // Should revert on zero amount
        vm.prank(address(core));
        token.escrowPayment(user1, 0);
    }

    function testEscrowMoreThanBalance() public {
        uint256 userBalance = token.balanceOf(user1);

        vm.expectRevert(SmartnodesERC20.Token__InsufficientBalance.selector);
        vm.prank(address(core));
        token.escrowPayment(user1, userBalance + 1);
    }

    function testEscrowExactBalance() public {
        uint256 amount = 1000e18;
        vm.prank(validator1);
        token.transfer(worker1, amount);

        vm.prank(address(core));
        token.escrowPayment(worker1, amount);

        assertEq(token.balanceOf(worker1), 0);
    }

    function testMultipleEscrowsSameUser() public {
        uint256 amount1 = 500e18;
        uint256 amount2 = 300e18;

        vm.prank(validator1);
        token.transfer(worker1, amount1 + amount2);

        vm.startPrank(address(core));
        token.escrowPayment(worker1, amount1);
        token.escrowPayment(worker1, amount2);
        vm.stopPrank();

        SmartnodesERC20.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(worker1);
        assertEq(escrowed.sno, amount1 + amount2);
    }

    function testEscrowEthWithWrongValue() public {
        uint256 paymentAmount = 1 ether;
        vm.deal(address(core), paymentAmount * 2);

        // Send less ETH than specified in parameter
        vm.prank(address(core));
        vm.expectRevert();
        token.escrowEthPayment{value: paymentAmount / 2}(user1, paymentAmount);
    }

    function testReleaseMoreThanEscrowed() public {
        uint256 escrowAmount = 500e18;
        uint256 releaseAmount = 600e18;

        // Setup escrow
        vm.prank(validator1);
        token.transfer(user1, escrowAmount);
        vm.prank(address(core));
        token.escrowPayment(user1, escrowAmount);

        // Try to release more than escrowed
        vm.expectRevert();
        vm.prank(address(core));
        token.releaseEscrowedPayment(user1, releaseAmount);
    }

    // ============= Merkle Distribution Edge Cases =============

    function testCreateDistributionWithZeroCapacity() public {
        _setupContractFunding();

        address[] memory validators = new address[](1);
        validators[0] = validator1;

        SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
            .PaymentAmounts({sno: 0, eth: 0});

        vm.prank(address(core));
        token.createMerkleDistribution(
            bytes32(0),
            0,
            validators,
            payments,
            validator1
        );
    }

    function testCreateDistributionWithEmptyValidators() public {
        _setupContractFunding();

        address[] memory validators = new address[](0);

        SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
            .PaymentAmounts({
                sno: uint128(ADDITIONAL_SNO_PAYMENT),
                eth: uint128(ADDITIONAL_ETH_PAYMENT)
            });

        vm.expectRevert(); // Should revert with empty validators array
        vm.prank(address(core));
        token.createMerkleDistribution(
            bytes32(0),
            1000,
            validators,
            payments,
            validator1
        );
    }

    function testClaimWithInvalidProof() public {
        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(3, false);
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        // Generate invalid proof (empty proof)
        bytes32[] memory invalidProof = new bytes32[](0);

        vm.expectRevert();
        vm.prank(participants[0].addr);
        token.claimMerkleRewards(
            distributionId,
            participants[0].capacity,
            invalidProof
        );
    }

    function testClaimWithWrongCapacity() public {
        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(3, false);
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        bytes32[] memory leaves = _generateLeaves(participants, distributionId);
        bytes32[] memory proof = _generateMerkleProof(leaves, 0);

        // Use wrong capacity
        vm.expectRevert();
        vm.prank(participants[0].addr);
        token.claimMerkleRewards(
            distributionId,
            participants[0].capacity + 1,
            proof
        );
    }

    function testDoubleClaimSameDistribution() public {
        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(1, false);
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );

        bytes32[] memory leaves = _generateLeaves(participants, distributionId);
        bytes32[] memory proof = _generateMerkleProof(leaves, 0);

        // First claim should succeed
        vm.prank(participants[0].addr);
        token.claimMerkleRewards(
            distributionId,
            participants[0].capacity,
            proof
        );

        // Second claim should revert
        vm.expectRevert(SmartnodesERC20.Token__RewardsAlreadyClaimed.selector);
        vm.prank(participants[0].addr);
        token.claimMerkleRewards(
            distributionId,
            participants[0].capacity,
            proof
        );
    }

    function testClaimFromNonexistentDistribution() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);

        vm.expectRevert();
        vm.prank(user1);
        token.claimMerkleRewards(999, 1000, proof);
    }

    // ============= Batch Operations Edge Cases =============

    function testBatchClaimWithMismatchedArrays() public {
        uint256[] memory distributionIds = new uint256[](2);
        uint256[] memory capacities = new uint256[](1); // Different length
        bytes32[][] memory proofs = new bytes32[][](2);

        vm.expectRevert();
        vm.prank(user1);
        token.batchClaimMerkleRewards(distributionIds, capacities, proofs);
    }

    // ============= Emission Rate Edge Cases =============

    function testEmissionRateAtExactYearBoundaries() public {
        uint256 start = token.i_deploymentTimestamp();

        uint256 rateAtBeginning = token.getEmissionRate();

        vm.warp(start + REWARD_PERIOD - 1);
        uint256 rateAtOneYearEnd = token.getEmissionRate();
        assertEq(rateAtOneYearEnd, rateAtBeginning); // still era 0

        vm.warp(start + REWARD_PERIOD);
        uint256 rateAtOneYear = token.getEmissionRate(); // era 1

        vm.warp(start + 2 * REWARD_PERIOD - 1);
        uint256 rateJustBeforeTwoYears = token.getEmissionRate();
        assertEq(rateAtOneYear, rateJustBeforeTwoYears); // still era 1

        vm.warp(start + 2 * REWARD_PERIOD);
        uint256 rateAtTwoYears = token.getEmissionRate(); // era 2
        assertTrue(rateAtTwoYears < rateAtOneYear);
    }

    function testEmissionRateNearTailEmission() public {
        // Calculate when we reach tail emission
        uint256 rate = INITIAL_EMISSION_RATE;
        uint256 _years = 0;

        while (rate > TAIL_EMISSION) {
            rate = (rate * 3) / 5;
            _years++;
        }

        // Go to just before tail emission threshold
        vm.warp(block.timestamp + (REWARD_PERIOD * (_years - 1)));
        assertTrue(token.getEmissionRate() > TAIL_EMISSION);

        // Go to tail emission threshold
        vm.warp(block.timestamp + REWARD_PERIOD);
        assertEq(token.getEmissionRate(), TAIL_EMISSION);
    }

    // ============= Gas Optimization Tests =============

    function testGasUsageForLargeDistribution() public {
        _setupContractFunding();
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(1000, false);

        uint256 gasStart = gasleft();
        (uint256 distributionId, ) = _createAndValidateDistribution(
            participants,
            totalCapacity
        );
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for 1000 participant distribution:", gasUsed);
        // You can add assertions here based on your gas requirements
    }

    function testOverflowProtection() public {
        // Test with very large numbers near uint256 max
        uint256 largeAmount = type(uint256).max;

        vm.expectRevert(); // Should revert due to overflow/insufficient balance
        vm.prank(address(core));
        token.escrowPayment(user1, largeAmount);
    }
}

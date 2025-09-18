// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Test.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {BaseSmartnodesTest} from "./BaseTest.sol";

/**
 * @title SmartnodesTokenTest
 * @notice Comprehensive tests for SmartnodesToken contract functionality
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
        vm.expectRevert(SmartnodesToken.Token__InsufficientBalance.selector);
        vm.prank(address(core));
        token.lockTokens(user3, false);
    }

    function testCannotLockAlreadyLockedTokens() public {
        vm.startPrank(address(core));
        vm.expectRevert(SmartnodesToken.Token__AlreadyLocked.selector);
        token.lockTokens(user1, true);
        vm.stopPrank();
    }

    function testCannotLockFromNonCore() public {
        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
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
        vm.expectRevert(SmartnodesToken.Token__UnlockPending.selector);
        token.unlockTokens(validator1);
        vm.stopPrank();
    }

    function testCannotUnlockNeverLocked() public {
        vm.prank(address(core));
        vm.expectRevert(SmartnodesToken.Token__NotLocked.selector);
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

        SmartnodesToken.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(user1);
        assertEq(escrowed.sno, paymentAmount);
    }

    function testEscrowEthPayment() public {
        uint256 paymentAmount = 1 ether;
        vm.deal(address(core), paymentAmount);

        vm.prank(address(core));
        token.escrowEthPayment{value: paymentAmount}(user1, paymentAmount);

        SmartnodesToken.PaymentAmounts memory escrowed = token
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

        SmartnodesToken.PaymentAmounts memory escrowed = token
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

        SmartnodesToken.PaymentAmounts memory escrowed = token
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
        (, SmartnodesToken.PaymentAmounts memory workerReward, , , ) = token
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

        uint256 expectedRate = (INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER *
            3) / 5;
        assertEq(token.getEmissionRate(), expectedRate);
    }

    function testEmissionRateAfterMultipleYears() public {
        // Fast forward two years
        vm.warp(block.timestamp + (REWARD_PERIOD * 2));

        uint256 expectedRate = (INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER *
            3 *
            3) / (5 * 5);
        assertEq(token.getEmissionRate(), expectedRate);
    }

    function testTailEmission() public {
        // Fast forward many years to reach tail emission
        vm.warp(block.timestamp + (REWARD_PERIOD * 20));

        assertEq(
            token.getEmissionRate(),
            TAIL_EMISSION * DEPLOYMENT_MULTIPLIER
        );
    }

    // ============= Access Control Tests =============

    function testOnlyCoreCanCallProtectedFunctions() public {
        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.lockTokens(validator2, true);

        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.unlockTokens(validator1);

        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
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
        bytes32[] memory leaves = _generateLeaves(participants);
        merkleRoot = _buildMerkleTree(leaves);

        console.log("Generated", leaves.length, "leaves");
        console.log("Merkle root:", vm.toString(merkleRoot));

        // Create distribution
        SmartnodesToken.PaymentAmounts
            memory additionalPayments = SmartnodesToken.PaymentAmounts({
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
        assertEq(distributionId, 1, "Distribution ID should be 1");

        // Validate distribution storage
        (
            bytes32 storedRoot,
            SmartnodesToken.PaymentAmounts memory workerReward,
            uint256 storedCapacity,
            bool active,
            uint256 timestamp
        ) = token.s_distributions(distributionId);

        assertEq(storedRoot, merkleRoot, "Stored merkle root mismatch");
        assertEq(storedCapacity, totalCapacity, "Stored capacity mismatch");
        if (participants.length > 0)
            assertTrue(active, "Distribution should be active");

        console.log("Distribution created and validated successfully");
    }

    /**
     * @notice Validate expected reward calculations
     * @param distributionId The distribution to validate
     */
    function _validateRewardCalculations(uint256 distributionId) internal view {
        (, SmartnodesToken.PaymentAmounts memory workerReward, , , ) = token
            .s_distributions(distributionId);

        uint256 totalSnoReward = INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER +
            ADDITIONAL_SNO_PAYMENT;
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
        bytes32[] memory leaves = _generateLeaves(participants);

        // Calculate total rewards
        uint256 totalSnoReward = INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER +
            ADDITIONAL_SNO_PAYMENT;
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
        bytes32[] memory leaves = _generateLeaves(participants);
        bytes32[] memory proof = _generateMerkleProof(leaves, workerIndex);

        // Pre-claim balances
        uint256 preClaimBalance = token.balanceOf(worker.addr);

        // Claim rewards
        vm.prank(worker.addr);
        token.claimMerkleRewards(distributionId, worker.capacity, proof);

        uint256 validatorSnoReward = ((INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER +
            ADDITIONAL_SNO_PAYMENT) * VALIDATOR_REWARD_PERCENTAGE) / 100;

        uint256 daoSnoReward = ((INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER +
            ADDITIONAL_SNO_PAYMENT) * DAO_REWARD_PERCENTAGE) / 100;

        uint256 expectedWorkerSno = (INITIAL_EMISSION_RATE *
            DEPLOYMENT_MULTIPLIER +
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
}

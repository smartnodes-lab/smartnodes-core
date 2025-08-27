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
    // Test constants
    uint256 constant INITIAL_EMISSION_RATE = 5832e18;
    uint256 constant TAIL_EMISSION = 512e18;
    uint256 constant VALIDATOR_LOCK_AMOUNT = 500_000e18;
    uint256 constant USER_LOCK_AMOUNT = 500e18;
    uint256 constant UNLOCK_PERIOD = 14 days;
    uint256 constant REWARD_PERIOD = 365 days;

    function _setupInitialState() internal override {
        // Token-specific setup
        addTestNetwork("Tensorlink");
        BaseSmartnodesTest._setupInitialState();
        createTestUser(user1, USER1_PUBKEY);

        // Ensure validators have enough tokens and ETH
        vm.deal(validator1, 10 ether);
        vm.deal(validator2, 10 ether);
        vm.deal(worker1, 5 ether);
        vm.deal(worker2, 5 ether);
        vm.deal(address(validator3), 10 ether);
        vm.deal(address(worker3), 5 ether);
        vm.deal(address(user2), 5 ether);
    }

    // ============= Core Contract Setup Tests =============

    function testSetSmartnodesCore() public {
        // Create a new token instance without core set
        address[] memory genesisNodes = new address[](1);
        genesisNodes[0] = validator1;

        SmartnodesToken newToken = new SmartnodesToken(genesisNodes);

        assertFalse(newToken.s_coreSet());
        assertEq(newToken.getSmartnodesCore(), address(0));

        // Set the core contract
        newToken.setSmartnodesCore(address(core));

        assertTrue(newToken.s_coreSet());
        assertEq(newToken.getSmartnodesCore(), address(core));
    }

    function testCannotSetCoreTwice() public {
        // Create a new token and set core first time
        address[] memory genesisNodes = new address[](1);
        genesisNodes[0] = validator1;

        SmartnodesToken newToken = new SmartnodesToken(genesisNodes);
        newToken.setSmartnodesCore(address(core));

        // Now try to set it again
        vm.expectRevert(SmartnodesToken.Token__CoreAlreadySet.selector);
        newToken.setSmartnodesCore(address(core));
    }

    function testCannotSetCoreToZeroAddress() public {
        address[] memory genesisNodes = new address[](1);
        genesisNodes[0] = validator1;

        SmartnodesToken newToken = new SmartnodesToken(genesisNodes);

        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
        newToken.setSmartnodesCore(address(0));
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
        assertEq(token.balanceOf(address(token)), VALIDATOR_LOCK_AMOUNT * 2); // validator1 + validator2
    }

    function testLockUserTokens() public {
        // First give user1 enough tokens
        vm.prank(validator1);
        token.transfer(user1, USER_LOCK_AMOUNT);

        uint256 initialUserBalance = token.balanceOf(user1);
        uint256 initialContractBalance = token.balanceOf(address(token));

        vm.prank(address(core));
        token.lockTokens(user1, false);

        // Check user tokens are locked
        assertEq(token.balanceOf(user1), initialUserBalance - USER_LOCK_AMOUNT);
        assertEq(
            token.balanceOf(address(token)),
            initialContractBalance + USER_LOCK_AMOUNT
        );
    }

    function testCannotLockInsufficientTokens() public {
        // user3 doesn't have enough tokens for user lock (500)
        vm.prank(address(core));
        vm.expectRevert(SmartnodesToken.Token__InsufficientBalance.selector);
        token.lockTokens(user3, false);
    }

    function testCannotLockAlreadyLockedTokens() public {
        vm.startPrank(address(core));
        vm.expectRevert(SmartnodesToken.Token__AlreadyLocked.selector);
        token.lockTokens(validator1, true);
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
        token.unlockTokens(user1);
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
        token.escrowPayment(user1, paymentAmount, 1);

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
        token.escrowEthPayment{value: paymentAmount}(user1, paymentAmount, 1);

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
        token.escrowPayment(user1, paymentAmount, 1);

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
        token.escrowEthPayment{value: paymentAmount}(user1, paymentAmount, 1);

        // Release ETH escrow
        vm.prank(address(core));
        token.releaseEscrowedEthPayment(user1, paymentAmount);

        SmartnodesToken.PaymentAmounts memory escrowed = token
            .getEscrowedPayments(user1);
        assertEq(escrowed.eth, 0);
        assertEq(address(token).balance, paymentAmount); // ETH stays in contract
    }

    // ============= Reward Distribution Tests =============

    function testMintRewards() public {
        address[] memory validators = new address[](2);
        validators[0] = address(validator3);
        validators[1] = validator2;

        address[] memory workers = new address[](2);
        workers[0] = address(worker3);
        workers[1] = worker2;

        uint256[] memory capacities = new uint256[](2);
        capacities[0] = 100;
        capacities[1] = 200;

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        // Check rewards were distributed
        SmartnodesToken.PaymentAmounts memory validator3Rewards = token
            .getUnclaimedRewards(address(validator3));
        SmartnodesToken.PaymentAmounts memory worker3Rewards = token
            .getUnclaimedRewards(address(worker3));

        assertTrue(validator3Rewards.sno > 0);
        assertTrue(validator3Rewards.eth > 0);
        assertTrue(worker3Rewards.sno > 0);
        assertTrue(worker3Rewards.eth > 0);
    }

    function testClaimTokenRewards() public {
        // Setup rewards first
        address[] memory validators = new address[](1);
        validators[0] = address(validator3);
        address[] memory workers = new address[](0);
        uint256[] memory capacities = new uint256[](0);

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 0});

        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        uint256 initialBalance = token.balanceOf(address(validator3));
        SmartnodesToken.PaymentAmounts memory rewards = token
            .getUnclaimedRewards(address(validator3));

        vm.prank(address(validator3));
        token.claimTokenRewards();

        assertEq(
            token.balanceOf(address(validator3)),
            initialBalance + rewards.sno
        );

        SmartnodesToken.PaymentAmounts memory newRewards = token
            .getUnclaimedRewards(address(validator3));
        assertEq(newRewards.sno, 0);
    }

    function testClaimEthRewards() public {
        // Setup ETH rewards
        address[] memory validators = new address[](1);
        validators[0] = address(validator3);
        address[] memory workers = new address[](0);
        uint256[] memory capacities = new uint256[](0);

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 0, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.deal(address(token), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        uint256 initialBalance = address(validator3).balance;
        SmartnodesToken.PaymentAmounts memory rewards = token
            .getUnclaimedRewards(address(validator3));

        vm.prank(address(validator3));
        token.claimEthRewards();

        assertEq(address(validator3).balance, initialBalance + rewards.eth);

        SmartnodesToken.PaymentAmounts memory newRewards = token
            .getUnclaimedRewards(address(validator3));
        assertEq(newRewards.eth, 0);
    }

    function testClaimAllRewards() public {
        // Setup both token and ETH rewards
        address[] memory validators = new address[](1);
        validators[0] = address(validator1);
        address[] memory workers = new address[](0);
        uint256[] memory capacities = new uint256[](0);

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.deal(address(token), 1 ether);
        vm.deal(address(validator1), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        uint256 initialTokenBalance = token.balanceOf(address(validator1));
        uint256 initialEthBalance = address(validator1).balance;
        SmartnodesToken.PaymentAmounts memory rewards = token
            .getUnclaimedRewards(address(validator1));

        vm.prank(address(validator1));
        token.claimAllRewards();

        assertEq(
            token.balanceOf(address(validator1)),
            initialTokenBalance + rewards.sno
        );
        assertEq(address(validator1).balance, initialEthBalance + rewards.eth);

        SmartnodesToken.PaymentAmounts memory newRewards = token
            .getUnclaimedRewards(address(validator1));
        assertEq(newRewards.sno, 0);
        assertEq(newRewards.eth, 0);
    }

    function testCannotClaimZeroRewards() public {
        vm.expectRevert(SmartnodesToken.Token__InsufficientBalance.selector);
        vm.prank(address(validator3));
        token.claimTokenRewards();
    }

    // ============= Emission Rate Tests =============

    function testInitialEmissionRate() public {
        assertEq(token.getEmissionRate(), INITIAL_EMISSION_RATE);
    }

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

    // ============= Worker Reward Distribution Tests =============

    function testWorkerRewardDistribution() public {
        address[] memory validators = new address[](0);
        address[] memory workers = new address[](3);
        workers[0] = worker1;
        workers[1] = worker2;
        workers[2] = address(worker3);

        uint256[] memory capacities = new uint256[](3);
        capacities[0] = 100; // 25% of total (400)
        capacities[1] = 150; // 37.5% of total
        capacities[2] = 150; // 37.5% of total

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        SmartnodesToken.PaymentAmounts memory worker1Rewards = token
            .getUnclaimedRewards(worker1);
        SmartnodesToken.PaymentAmounts memory worker2Rewards = token
            .getUnclaimedRewards(worker2);
        SmartnodesToken.PaymentAmounts memory worker3Rewards = token
            .getUnclaimedRewards(address(worker3));

        // Worker2 and Worker3 should have same rewards (same capacity)
        assertEq(worker2Rewards.sno, worker3Rewards.sno);
        assertEq(worker2Rewards.eth, worker3Rewards.eth);

        // Worker1 should have less (smaller capacity)
        assertTrue(worker1Rewards.sno < worker2Rewards.sno);
        assertTrue(worker1Rewards.eth < worker2Rewards.eth);
    }

    // ============= Edge Cases Tests =============

    function testMintRewardsWithNoValidators() public {
        address[] memory validators = new address[](0);
        address[] memory workers = new address[](1);
        workers[0] = worker1;

        uint256[] memory capacities = new uint256[](1);
        capacities[0] = 100;

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        // Should still work, just no validator rewards
        SmartnodesToken.PaymentAmounts memory workerRewards = token
            .getUnclaimedRewards(worker1);
        assertTrue(workerRewards.sno > 0);
    }

    function testMintRewardsWithNoWorkers() public {
        address[] memory validators = new address[](1);
        validators[0] = address(validator3);
        address[] memory workers = new address[](0);
        uint256[] memory capacities = new uint256[](0);

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        SmartnodesToken.PaymentAmounts memory validatorRewards = token
            .getUnclaimedRewards(address(validator3));
        assertTrue(validatorRewards.sno > 0);
    }

    function testMintRewardsWithZeroCapacities() public {
        address[] memory validators = new address[](1);
        validators[0] = address(validator3);
        address[] memory workers = new address[](2);
        workers[0] = worker1;
        workers[1] = worker2;

        uint256[] memory capacities = new uint256[](2);
        capacities[0] = 0;
        capacities[1] = 0;

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        // Workers should have no rewards due to zero capacity
        SmartnodesToken.PaymentAmounts memory worker1Rewards = token
            .getUnclaimedRewards(worker1);
        SmartnodesToken.PaymentAmounts memory worker2Rewards = token
            .getUnclaimedRewards(worker2);
        assertEq(worker1Rewards.sno, 0);
        assertEq(worker2Rewards.sno, 0);

        // Validator should still get rewards
        SmartnodesToken.PaymentAmounts memory validatorRewards = token
            .getUnclaimedRewards(address(validator3));
        assertTrue(validatorRewards.sno > 0);
    }

    // ============= View Function Tests =============

    function testGetTotalClaimed() public {
        // Setup and claim rewards
        address[] memory validators = new address[](1);
        validators[0] = address(validator3);
        address[] memory workers = new address[](2);
        uint256[] memory capacities = new uint256[](2);
        workers[0] = worker1;
        workers[1] = worker2;
        capacities[0] = 100;
        capacities[1] = 250;

        SmartnodesToken.PaymentAmounts memory payments = SmartnodesToken
            .PaymentAmounts({sno: 1000e18, eth: 1 ether});

        vm.deal(address(core), 1 ether);
        vm.deal(address(token), 1 ether);
        vm.prank(address(core));
        token.mintRewards(validators, workers, capacities, payments);

        // Get rewards for worker1 before claiming
        SmartnodesToken.PaymentAmounts memory rewardsBefore = token
            .getUnclaimedRewards(worker1);

        vm.prank(worker1);
        token.claimAllRewards();

        SmartnodesToken.PaymentAmounts memory totalClaimed = token
            .getTotalClaimed(worker1);
        assertEq(totalClaimed.sno, rewardsBefore.sno);
        assertEq(totalClaimed.eth, rewardsBefore.eth);
    }

    // ============= Access Control Tests =============

    function testOnlyOwnerCanSetCore() public {
        address[] memory genesisNodes = new address[](1);
        genesisNodes[0] = validator1;

        SmartnodesToken newToken = new SmartnodesToken(genesisNodes);

        vm.expectRevert(); // Should revert with Ownable error
        vm.prank(validator1);
        newToken.setSmartnodesCore(address(core));
    }

    function testOnlyCoreCanCallProtectedFunctions() public {
        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.lockTokens(validator2, true);

        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.unlockTokens(validator1);

        vm.expectRevert(SmartnodesToken.Token__InvalidAddress.selector);
        vm.prank(validator1);
        token.escrowPayment(user1, 1000e18, 1);
    }
}

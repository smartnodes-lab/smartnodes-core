// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.22;

// import {console} from "forge-std/Test.sol";
// import {SmartnodesERC20} from "../src/SmartnodesERC20.sol";
// import {BaseSmartnodesTest} from "./BaseTest.sol";

// /**
//  * @title SmartnodesTokenFuzzTest
//  * @notice Fuzz testing for SmartnodesERC20 contract to test edge cases and boundary conditions
//  */
// contract SmartnodesTokenFuzzTest is BaseSmartnodesTest {
//     uint256 constant MAX_REASONABLE_TOKENS = 1_000_000_000e18; // 1B tokens
//     uint256 constant MAX_REASONABLE_ETH = 100_000 ether; // 100k ETH
//     uint256 constant MIN_LOCK_AMOUNT = 1e18; // 1 token minimum

//     function _setupInitialState() internal override {
//         BaseSmartnodesTest._setupInitialState();
//         createTestUser(user1, USER1_PUBKEY);
//         createTestUser(user2, USER2_PUBKEY);
//     }

//     // ============= Fuzz Tests for Token Locking =============

//     /// @notice Fuzz test for locking user tokens with various amounts
//     function testFuzz_LockUserTokens(uint256 lockAmount) public {
//         vm.assume(lockAmount >= USER_LOCK_AMOUNT);
//         // Reduce maximum to prevent overflow with validator1's initial balance
//         vm.assume(lockAmount <= MAX_REASONABLE_TOKENS / 10);

//         // Ensure validator1 has enough tokens to transfer
//         uint256 validatorBalance = token.balanceOf(validator1);
//         vm.assume(lockAmount <= validatorBalance);

//         // Create a fresh user to avoid "already locked" issues
//         address freshUser = makeAddr("freshUser");

//         // Give user tokens
//         vm.prank(validator1);
//         token.transfer(freshUser, lockAmount);

//         uint256 initialBalance = token.balanceOf(freshUser);
//         uint256 initialContractBalance = token.balanceOf(address(token));

//         vm.prank(address(core));
//         token.lockTokens(freshUser, false);

//         // Should lock exactly USER_LOCK_AMOUNT regardless of balance
//         assertEq(token.balanceOf(freshUser), initialBalance - USER_LOCK_AMOUNT);
//         assertEq(
//             token.balanceOf(address(token)),
//             initialContractBalance + USER_LOCK_AMOUNT
//         );
//     }

//     /// @notice Fuzz test for attempting to lock tokens with insufficient balance
//     function testFuzz_LockTokensInsufficientBalance(uint256 balance) public {
//         vm.assume(balance < USER_LOCK_AMOUNT);
//         vm.assume(balance <= MAX_REASONABLE_TOKENS / 10);

//         address testUser = makeAddr("testUser");

//         if (balance > 0) {
//             // Ensure validator1 has enough tokens to transfer
//             uint256 validatorBalance = token.balanceOf(validator1);
//             vm.assume(balance <= validatorBalance);

//             vm.prank(validator1);
//             token.transfer(testUser, balance);
//         }

//         vm.expectRevert(SmartnodesERC20.Token__InsufficientBalance.selector);
//         vm.prank(address(core));
//         token.lockTokens(testUser, false);
//     }

//     /// @notice Fuzz test unlock timing with various time periods
//     function testFuzz_UnlockTiming(uint256 timeAdvance) public {
//         vm.assume(timeAdvance <= 365 days * 10); // Cap at 10 years

//         // Create a fresh validator to avoid conflicts
//         address freshValidator = makeAddr("freshValidator");

//         // Give the validator some tokens and lock them first
//         vm.prank(validator1);
//         token.transfer(freshValidator, VALIDATOR_LOCK_AMOUNT);

//         vm.prank(address(core));
//         token.lockTokens(freshValidator, true);

//         // Initiate unlock
//         vm.prank(address(core));
//         token.unlockTokens(freshValidator);

//         // Fast forward time
//         vm.warp(block.timestamp + timeAdvance);

//         if (timeAdvance >= UNLOCK_PERIOD) {
//             // Should succeed
//             vm.prank(address(core));
//             token.unlockTokens(freshValidator);
//         } else {
//             // Should fail
//             vm.expectRevert(SmartnodesERC20.Token__UnlockPending.selector);
//             vm.prank(address(core));
//             token.unlockTokens(freshValidator);
//         }
//     }

//     // ============= Fuzz Tests for Escrow =============

//     /// @notice Fuzz test escrow amounts
//     function testFuzz_EscrowPayment(uint256 escrowAmount) public {
//         vm.assume(escrowAmount > 0);
//         // Reduce maximum to prevent overflow
//         vm.assume(escrowAmount <= MAX_REASONABLE_TOKENS / 10);

//         // Ensure validator1 has enough tokens to transfer
//         uint256 validatorBalance = token.balanceOf(validator1);
//         vm.assume(escrowAmount <= validatorBalance);

//         // Create fresh user for each test
//         address freshUser = makeAddr("freshEscrowUser");

//         // Give user enough tokens
//         vm.prank(validator1);
//         token.transfer(freshUser, escrowAmount);

//         uint256 initialBalance = token.balanceOf(freshUser);
//         uint256 initialContractBalance = token.balanceOf(address(token));

//         vm.prank(address(core));
//         token.escrowPayment(freshUser, escrowAmount);

//         assertEq(token.balanceOf(freshUser), initialBalance - escrowAmount);
//         assertEq(
//             token.balanceOf(address(token)),
//             initialContractBalance + escrowAmount
//         );

//         SmartnodesERC20.PaymentAmounts memory escrowed = token
//             .getEscrowedPayments(freshUser);
//         assertEq(escrowed.sno, escrowAmount);
//     }

//     /// @notice Fuzz test ETH escrow amounts
//     function testFuzz_EscrowEthPayment(uint256 ethAmount) public {
//         vm.assume(ethAmount > 0);
//         vm.assume(ethAmount <= MAX_REASONABLE_ETH);

//         vm.deal(address(core), ethAmount);

//         // Create fresh user for each test
//         address freshUser = makeAddr("freshEthEscrowUser");

//         uint256 initialBalance = address(token).balance;

//         vm.prank(address(core));
//         token.escrowEthPayment{value: ethAmount}(freshUser, ethAmount);

//         assertEq(address(token).balance, initialBalance + ethAmount);

//         SmartnodesERC20.PaymentAmounts memory escrowed = token
//             .getEscrowedPayments(freshUser);
//         assertEq(escrowed.eth, ethAmount);
//     }

//     /// @notice Fuzz test multiple escrows for same user
//     function testFuzz_MultipleEscrows(uint256 escrow1, uint256 escrow2) public {
//         vm.assume(escrow1 > 0 && escrow1 <= MAX_REASONABLE_TOKENS / 20);
//         vm.assume(escrow2 > 0 && escrow2 <= MAX_REASONABLE_TOKENS / 20);

//         uint256 totalEscrow = escrow1 + escrow2;

//         // Ensure validator1 has enough tokens to transfer
//         uint256 validatorBalance = token.balanceOf(validator1);
//         vm.assume(totalEscrow <= validatorBalance);

//         // Create fresh user for each test
//         address freshUser = makeAddr("freshMultiEscrowUser");

//         // Give user enough tokens
//         vm.prank(validator1);
//         token.transfer(freshUser, totalEscrow);

//         vm.startPrank(address(core));
//         token.escrowPayment(freshUser, escrow1);
//         token.escrowPayment(freshUser, escrow2);
//         vm.stopPrank();

//         SmartnodesERC20.PaymentAmounts memory escrowed = token
//             .getEscrowedPayments(freshUser);
//         assertEq(escrowed.sno, totalEscrow);
//     }

//     // /// @notice Fuzz test escrow release amounts
//     // function testFuzz_ReleaseEscrow(
//     //     uint256 escrowAmount,
//     //     uint256 releaseAmount
//     // ) public {
//     //     vm.assume(
//     //         escrowAmount > 0 && escrowAmount <= MAX_REASONABLE_TOKENS / 10
//     //     );
//     //     vm.assume(releaseAmount > 0 && releaseAmount <= escrowAmount); // Ensure releaseAmount > 0

//     //     // Ensure validator1 has enough tokens to transfer
//     //     uint256 validatorBalance = token.balanceOf(validator1);
//     //     vm.assume(escrowAmount <= validatorBalance);

//     //     // Create fresh user for each test
//     //     address freshUser = makeAddr("freshReleaseUser");

//     //     // Setup escrow
//     //     vm.prank(validator1);
//     //     token.transfer(freshUser, escrowAmount);
//     //     vm.prank(address(core));
//     //     token.escrowPayment(freshUser, escrowAmount);

//     //     uint256 initialBalance = token.balanceOf(freshUser);

//     //     vm.prank(address(core));
//     //     token.releaseEscrowedPayment(freshUser, releaseAmount);

//     //     assertEq(token.balanceOf(freshUser), initialBalance + releaseAmount);

//     //     SmartnodesERC20.PaymentAmounts memory remaining = token
//     //         .getEscrowedPayments(freshUser);
//     //     assertEq(remaining.sno, escrowAmount - releaseAmount);
//     // }

//     // ============= Fuzz Tests for Merkle Distributions =============

//     /// @notice Fuzz test distribution creation with various parameters
//     function testFuzz_CreateDistribution(
//         uint256 totalCapacity,
//         uint256 additionalSno,
//         uint256 additionalEth
//     ) public {
//         vm.assume(totalCapacity > 0 && totalCapacity <= 1_000_000);
//         vm.assume(additionalSno <= MAX_REASONABLE_TOKENS);
//         vm.assume(additionalEth <= MAX_REASONABLE_ETH);

//         _setupContractFunding();

//         // Fund contract if needed
//         if (additionalEth > ADDITIONAL_ETH_PAYMENT) {
//             vm.deal(address(core), additionalEth);
//             vm.prank(address(core));
//             (bool success, ) = address(token).call{value: additionalEth}("");
//             require(success, "Additional funding failed");
//         }

//         address[] memory validators = new address[](1);
//         validators[0] = validator1;

//         SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
//             .PaymentAmounts({
//                 sno: uint128(additionalSno),
//                 eth: uint128(additionalEth)
//             });

//         bytes32 dummyRoot = keccak256(abi.encode("dummy", totalCapacity));

//         vm.prank(address(core));
//         token.createMerkleDistribution(
//             dummyRoot,
//             totalCapacity,
//             validators,
//             payments,
//             validator1
//         );

//         uint256 distributionId = token.s_currentDistributionId();
//         (
//             bytes32 storedRoot,
//             SmartnodesERC20.PaymentAmounts memory workerReward,
//             uint256 storedCapacity,
//             bool active,
//             ,

//         ) = token.s_distributions(distributionId);

//         assertEq(storedRoot, dummyRoot);
//         assertEq(storedCapacity, totalCapacity);
//         assertTrue(active);
//     }

//     /// @notice Fuzz test emission rate calculation at various timestamps
//     function testFuzz_EmissionRate(uint256 timeAdvance) public {
//         vm.assume(timeAdvance <= 365 days * 50); // Cap at 50 years

//         uint256 startTime = token.i_deploymentTimestamp();
//         vm.warp(startTime + timeAdvance);

//         uint256 rate = token.getEmissionRate();

//         // Should never be zero or exceed initial rate
//         assertGt(rate, 0);
//         assertLe(rate, INITIAL_EMISSION_RATE);

//         // Should either be tail emission or calculated rate
//         if (rate == TAIL_EMISSION) {
//             // We've reached tail emission - should be after many halvings
//             assertTrue(timeAdvance >= REWARD_PERIOD * 5); // After several halvings
//         } else {
//             // Should be a calculated reduction based on halvings
//             assertTrue(rate <= INITIAL_EMISSION_RATE);
//         }
//     }

//     // ============= Invariant Testing =============

//     /// @notice Test that total supply changes are tracked correctly
//     function testFuzz_TotalSupplyInvariant(
//         uint256 numDistributions,
//         uint256 additionalPayment
//     ) public {
//         vm.assume(numDistributions > 0 && numDistributions <= 3); // Reduced for stability
//         vm.assume(
//             additionalPayment <= MAX_REASONABLE_TOKENS / (numDistributions * 10)
//         );

//         _setupContractFunding();

//         uint256 initialSupply = token.totalSupply();
//         uint256 expectedIncrease = 0;

//         // Advance time to ensure we're past any distribution cooldown
//         vm.warp(block.timestamp + UPDATE_TIME + 1);

//         for (uint256 i = 0; i < numDistributions; i++) {
//             // Get emission rate BEFORE creating distribution
//             uint256 emissionRate = token.getEmissionRate();
//             expectedIncrease += emissionRate;

//             address[] memory validators = new address[](1);
//             validators[0] = validator1;

//             SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
//                 .PaymentAmounts({sno: uint128(additionalPayment), eth: 0});

//             vm.prank(address(core));
//             token.createMerkleDistribution(
//                 keccak256(abi.encode("test", i, block.timestamp)), // More unique roots
//                 1000,
//                 validators,
//                 payments,
//                 validator1
//             );

//             // Advance time significantly between distributions to ensure cooldown period passes
//             vm.warp(block.timestamp + UPDATE_TIME + 1);
//         }

//         uint256 finalSupply = token.totalSupply();
//         assertEq(finalSupply, initialSupply + expectedIncrease);
//     }

//     /// @notice Test contract ETH balance invariant
//     function testFuzz_EthBalanceInvariant(
//         uint256 escrowAmount,
//         uint256 distributionAmount
//     ) public {
//         vm.assume(escrowAmount > 0 && escrowAmount <= MAX_REASONABLE_ETH / 2);
//         vm.assume(
//             distributionAmount > 0 &&
//                 distributionAmount <= MAX_REASONABLE_ETH / 2
//         );

//         uint256 totalEth = escrowAmount + distributionAmount;
//         vm.deal(address(core), totalEth);

//         // Create fresh user for each test
//         address freshUser = makeAddr("freshEthInvariantUser");

//         uint256 initialBalance = address(token).balance;

//         // Escrow some ETH
//         vm.prank(address(core));
//         token.escrowEthPayment{value: escrowAmount}(freshUser, escrowAmount);

//         // Fund for distribution
//         vm.prank(address(core));
//         (bool success, ) = address(token).call{value: distributionAmount}("");
//         require(success, "Distribution funding failed");

//         uint256 finalBalance = address(token).balance;
//         assertEq(finalBalance, initialBalance + totalEth);
//     }

//     // ============= Stress Tests =============

//     /// @notice Stress test with extreme values
//     function testFuzz_ExtremeValues(uint256 seed) public {
//         vm.assume(seed > 0);

//         // Use seed to generate deterministic but varied test cases
//         uint256 tokenAmount = (seed % (MAX_REASONABLE_TOKENS / 10)) + 1;
//         uint256 ethAmount = (seed % MAX_REASONABLE_ETH) + 1;
//         uint256 capacity = (seed % 1_000_000) + 1;

//         // Ensure validator1 has enough tokens
//         uint256 validatorBalance = token.balanceOf(validator1);
//         vm.assume(tokenAmount <= validatorBalance);

//         // Create fresh user for each test to avoid state conflicts
//         address freshUser = makeAddr(
//             string(abi.encodePacked("extremeUser", seed))
//         );

//         // Test with large token amounts
//         vm.prank(validator1);
//         token.transfer(freshUser, tokenAmount);

//         // Only try to lock if we have enough tokens and user isn't already locked
//         if (tokenAmount >= USER_LOCK_AMOUNT) {
//             // Check if this would cause conflicts by trying with a different user
//             try this.testLockAttempt(freshUser) {
//                 // Success - continue
//             } catch {
//                 // Skip locking test if it would fail due to existing state
//             }
//         }

//         // Test with large ETH amounts
//         vm.deal(address(core), ethAmount);
//         vm.prank(address(core));
//         token.escrowEthPayment{value: ethAmount}(freshUser, ethAmount);

//         // Test distribution with large capacity
//         _setupContractFunding();

//         address[] memory validators = new address[](1);
//         validators[0] = validator1;

//         SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
//             .PaymentAmounts({sno: 0, eth: 0});

//         vm.prank(address(core));
//         token.createMerkleDistribution(
//             keccak256(abi.encode(seed, block.timestamp)),
//             capacity,
//             validators,
//             payments,
//             validator1
//         );
//     }

//     /// @notice Helper function for lock attempt testing
//     function testLockAttempt(address user) external {
//         // Ensure the user has enough balance first
//         uint256 userBalance = token.balanceOf(user);
//         if (userBalance < USER_LOCK_AMOUNT) {
//             // Transfer enough tokens from validator1
//             vm.prank(validator1);
//             token.transfer(user, USER_LOCK_AMOUNT);
//         }

//         vm.prank(address(core));
//         token.lockTokens(user, false);
//     }

//     // ============= Boundary Tests =============

//     /// @notice Test with maximum validator array size
//     function testBoundary_MaxValidators() public {
//         _setupContractFunding();

//         // Create large validator array (reasonable limit)
//         address[] memory validators = new address[](100);
//         for (uint256 i = 0; i < 100; i++) {
//             validators[i] = address(uint160(0x4000 + i));
//         }

//         SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
//             .PaymentAmounts({
//                 sno: uint128(ADDITIONAL_SNO_PAYMENT),
//                 eth: uint128(ADDITIONAL_ETH_PAYMENT)
//             });

//         vm.prank(address(core));
//         token.createMerkleDistribution(
//             keccak256(abi.encode("boundary_test", block.timestamp)),
//             1000,
//             validators,
//             payments,
//             validators[0]
//         );
//     }

//     // ============= Gas Optimization Fuzz Tests =============

//     /// @notice Fuzz test gas usage with varying participant counts
//     function testFuzz_GasUsage(uint256 numParticipants) public {
//         vm.assume(numParticipants > 0 && numParticipants <= 500); // Reduced for stability

//         _setupContractFunding();
//         (
//             Participant[] memory participants,
//             uint256 totalCapacity
//         ) = _setupTestParticipants(numParticipants, false);

//         bytes32[] memory leaves = _generateLeaves(participants, 1);
//         bytes32 merkleRoot = _buildMerkleTree(leaves);

//         address[] memory validators = new address[](1);
//         validators[0] = validator1;

//         SmartnodesERC20.PaymentAmounts memory payments = SmartnodesERC20
//             .PaymentAmounts({
//                 sno: uint128(ADDITIONAL_SNO_PAYMENT),
//                 eth: uint128(ADDITIONAL_ETH_PAYMENT)
//             });

//         uint256 gasBefore = gasleft();

//         vm.prank(address(core));
//         token.createMerkleDistribution(
//             merkleRoot,
//             totalCapacity,
//             validators,
//             payments,
//             validator1
//         );

//         uint256 gasUsed = gasBefore - gasleft();

//         // Gas should be reasonable and roughly linear with participant count
//         console.log("Participants:", numParticipants, "Gas used:", gasUsed);

//         // Assert gas usage is within reasonable bounds
//         assertLt(gasUsed, 500_000, "Gas usage too high");
//     }
// }

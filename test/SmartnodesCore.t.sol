// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";

// Mock contracts for testing
contract MockSmartnodesMultiSig {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function executeTransaction(address target, bytes calldata data) external {
        (bool success, ) = target.call(data);
        require(success, "Transaction failed");
    }
}

contract MockSmartnodesCore {
    function escrowPayment(
        address user,
        uint256 amount,
        uint8 networkId
    ) external {}

    function releaseEscrow(address user, uint256 amount) external {}

    function createValidatorLock(address validator) external {}

    function unlockValidatorTokens(address validator) external {}

    function mintRewards(
        address[] calldata workers,
        address[] calldata validatorsVoted,
        uint256[] calldata workerCapacities,
        uint256 additionalReward
    ) external {}
}

contract SmartnodesTest is Test {
    SmartnodesToken public token;
    SmartnodesCore public core;
    MockSmartnodesMultiSig public multisig;
    MockSmartnodesCore public mockCore;

    address public deployer = makeAddr("deployer");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public worker1 = makeAddr("worker1");
    address public worker2 = makeAddr("worker2");

    address[] public genesisNodes;

    uint256 public constant LOCK_AMOUNT = 250_000e18;
    uint256 public constant INITIAL_EMISSION_RATE = 5832e18;
    uint256 public constant TAIL_EMISSION = 512e18;

    event PaymentEscrowed(address user, uint256 payment, uint8 networkId);
    event EscrowReleased(address user, uint256 amount);
    event JobCreated(
        bytes32 indexed jobId,
        uint8 indexed networkId,
        address indexed requester,
        uint128 payment
    );
    event JobCompleted(
        bytes32 indexed jobId,
        uint8 indexed networkId,
        address indexed requester
    );
    event JobCancelled(
        bytes32 indexed jobId,
        uint8 indexed networkId,
        address indexed requester
    );
    event ValidatorCreated(address indexed validator, bytes32 publicKeyHash);
    event ValidatorUnlockInitiated(
        address indexed validator,
        uint64 unlockTime
    );
    event ValidatorUnlocked(address indexed validator);

    function setUp() public {
        vm.startPrank(deployer);

        // Setup genesis nodes
        genesisNodes.push(validator1);
        genesisNodes.push(validator2);

        // Deploy multisig mock
        multisig = new MockSmartnodesMultiSig();

        // Deploy mock core first for token constructor
        mockCore = new MockSmartnodesCore();

        // Deploy token with mock core
        token = new SmartnodesToken(genesisNodes, address(mockCore));

        // Deploy actual core
        core = new SmartnodesCore(
            address(token),
            address(multisig),
            genesisNodes
        );

        vm.stopPrank();
    }

    // ============ SmartnodesToken Tests =============

    function test_TokenDeployment() public {
        assertEq(token.name(), "Smartnodes");
        assertEq(token.symbol(), "SNO");
        assertEq(token.balanceOf(validator1), LOCK_AMOUNT);
        assertEq(token.balanceOf(validator2), LOCK_AMOUNT);
        assertEq(token.totalSupply(), LOCK_AMOUNT * 2);
    }

    function test_EmissionRateCalculation() public {
        // Test initial emission rate
        assertEq(token.getEmissionRate(), INITIAL_EMISSION_RATE);

        // Test emission after 1 year (should be 2/3 of initial)
        vm.warp(block.timestamp + 365 days);
        uint256 expectedEmission = (INITIAL_EMISSION_RATE * 2) / 3;
        assertEq(token.getEmissionRate(), expectedEmission);

        // Test emission after 2 years
        vm.warp(block.timestamp + 365 days);
        expectedEmission = (expectedEmission * 2) / 3;
        assertEq(token.getEmissionRate(), expectedEmission);

        // Test tail emission (simulate many years)
        vm.warp(block.timestamp + 365 days * 20);
        assertEq(token.getEmissionRate(), TAIL_EMISSION);
    }

    function test_EscrowPayment() public {
        vm.startPrank(address(mockCore));

        // Give user1 some tokens
        vm.startPrank(validator1);
        token.transfer(user1, 1000e18);
        vm.stopPrank();

        vm.startPrank(address(mockCore));

        vm.expectEmit(true, true, true, true);
        emit PaymentEscrowed(user1, 500e18, 1);

        token.escrowPayment(user1, 500e18, 1);

        assertEq(token.balanceOf(user1), 500e18);
        assertEq(token.balanceOf(address(token)), 500e18);

        vm.stopPrank();
    }

    function test_EscrowPayment_RevertZeroAddress() public {
        vm.startPrank(address(mockCore));

        vm.expectRevert(SmartnodesToken.SmartnodesToken__ZeroAddress.selector);
        token.escrowPayment(address(0), 500e18, 1);

        vm.stopPrank();
    }

    function test_EscrowPayment_RevertZeroAmount() public {
        vm.startPrank(address(mockCore));

        vm.expectRevert(
            SmartnodesToken.SmartnodesToken__InvalidPayment.selector
        );
        token.escrowPayment(user1, 0, 1);

        vm.stopPrank();
    }

    function test_EscrowPayment_RevertInsufficientBalance() public {
        vm.startPrank(address(mockCore));

        vm.expectRevert(
            SmartnodesToken.SmartnodesToken__InsufficientBalance.selector
        );
        token.escrowPayment(user1, 1000e18, 1);

        vm.stopPrank();
    }

    function test_EscrowPayment_RevertInvalidCaller() public {
        vm.startPrank(user1);

        vm.expectRevert(
            SmartnodesToken.SmartnodesToken__InvalidCaller.selector
        );
        token.escrowPayment(user1, 500e18, 1);

        vm.stopPrank();
    }

    function test_ReleaseEscrow() public {
        // First escrow some payment
        vm.startPrank(validator1);
        token.transfer(user1, 1000e18);
        vm.stopPrank();

        vm.startPrank(address(mockCore));
        token.escrowPayment(user1, 500e18, 1);

        vm.expectEmit(true, true, true, true);
        emit EscrowReleased(user1, 300e18);

        token.releaseEscrow(user1, 300e18);

        assertEq(token.balanceOf(user1), 800e18);
        assertEq(token.balanceOf(address(token)), 200e18);

        vm.stopPrank();
    }

    function test_CreateValidatorLock() public {
        // Give validator some tokens
        vm.startPrank(validator1);
        token.transfer(user1, LOCK_AMOUNT);
        vm.stopPrank();

        vm.startPrank(address(mockCore));
        token.createValidatorLock(user1);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(address(token)), LOCK_AMOUNT);

        vm.stopPrank();
    }

    function test_UnlockValidatorTokens() public {
        // First lock tokens
        vm.startPrank(validator1);
        token.transfer(user1, LOCK_AMOUNT);
        vm.stopPrank();

        vm.startPrank(address(mockCore));
        token.createValidatorLock(user1);

        // Now unlock
        token.unlockValidatorTokens(user1);

        assertEq(token.balanceOf(user1), LOCK_AMOUNT);
        assertEq(token.balanceOf(address(token)), 0);

        vm.stopPrank();
    }

    function test_MintRewards() public {
        vm.startPrank(address(mockCore));

        address[] memory workers = new address[](2);
        workers[0] = worker1;
        workers[1] = worker2;

        address[] memory validators = new address[](2);
        validators[0] = validator1;
        validators[1] = validator2;

        uint256[] memory capacities = new uint256[](2);
        capacities[0] = 100;
        capacities[1] = 200;

        token.mintRewards(workers, validators, capacities, 1000e18);

        // Check that rewards were distributed (note: they're unclaimed until claimed)
        vm.stopPrank();

        // Workers and validators should be able to claim rewards
        vm.startPrank(worker1);
        uint256 balanceBefore = token.balanceOf(worker1);
        token.claimRewards();
        assertGt(token.balanceOf(worker1), balanceBefore);
        vm.stopPrank();

        vm.startPrank(validator1);
        balanceBefore = token.balanceOf(validator1);
        token.claimRewards();
        assertGt(token.balanceOf(validator1), balanceBefore);
        vm.stopPrank();
    }

    function test_ClaimRewards_NoRewards() public {
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        token.claimRewards();
        assertEq(token.balanceOf(user1), balanceBefore);
        vm.stopPrank();
    }

    // ============ SmartnodesCore Tests =============

    function test_CoreDeployment() public {
        assertTrue(core.validatorExists(validator1));
        assertTrue(core.validatorExists(validator2));
    }

    function test_RequestJob() public {
        // First add a network
        vm.startPrank(address(token));
        core.addNetwork("Test Network");
        vm.stopPrank();

        // Give user some tokens and approve
        vm.startPrank(validator1);
        token.transfer(user1, 10000e18);
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(core), 1000e18);

        bytes32 jobId = keccak256("test_job_1");
        uint64[] memory capacities = new uint64[](2);
        capacities[0] = 100;
        capacities[1] = 200;

        vm.expectEmit(true, true, true, true);
        emit JobCreated(jobId, 0, user1, 1000e18);

        core.requestJob(jobId, 0, capacities, 1000e18);

        (
            uint128 payment,
            address requester,
            uint8 networkId,
            bool exists
        ) = core.getJobInfo(jobId);
        assertEq(payment, 1000e18);
        assertEq(requester, user1);
        assertEq(networkId, 0);
        assertTrue(exists);

        vm.stopPrank();
    }

    function test_RequestJob_RevertZeroPayment() public {
        vm.startPrank(address(token));
        core.addNetwork("Test Network");
        vm.stopPrank();

        vm.startPrank(user1);
        bytes32 jobId = keccak256("test_job_1");
        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        vm.expectRevert(SmartnodesCore.SmartnodesCore__ZeroPayment.selector);
        core.requestJob(jobId, 0, capacities, 0);

        vm.stopPrank();
    }

    function test_RequestJob_RevertInvalidNetwork() public {
        vm.startPrank(user1);
        bytes32 jobId = keccak256("test_job_1");
        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__InvalidNetworkId.selector
        );
        core.requestJob(jobId, 99, capacities, 1000e18);

        vm.stopPrank();
    }

    function test_CancelJob() public {
        // Setup: create a job first
        vm.startPrank(address(token));
        core.addNetwork("Test Network");
        vm.stopPrank();

        vm.startPrank(validator1);
        token.transfer(user1, 10000e18);
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(core), 1000e18);

        bytes32 jobId = keccak256("test_job_1");
        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        core.requestJob(jobId, 0, capacities, 1000e18);

        vm.expectEmit(true, true, true, true);
        emit JobCancelled(jobId, 0, user1);

        core.cancelJob(jobId);

        (, , , bool exists) = core.getJobInfo(jobId);
        assertFalse(exists);

        vm.stopPrank();
    }

    function test_CancelJob_RevertUnauthorized() public {
        // Setup: create a job first
        vm.startPrank(address(token));
        core.addNetwork("Test Network");
        vm.stopPrank();

        vm.startPrank(validator1);
        token.transfer(user1, 10000e18);
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(core), 1000e18);

        bytes32 jobId = keccak256("test_job_1");
        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        core.requestJob(jobId, 0, capacities, 1000e18);
        vm.stopPrank();

        // Try to cancel from different user
        vm.startPrank(user2);
        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__UnauthorizedJobCancellation.selector
        );
        core.cancelJob(jobId);
        vm.stopPrank();
    }

    function test_CreateValidator() public {
        vm.startPrank(address(multisig));

        bytes32 publicKeyHash = keccak256("new_validator_key");

        vm.expectEmit(true, true, true, true);
        emit ValidatorCreated(user1, publicKeyHash);

        core.createValidator(publicKeyHash, user1);

        assertTrue(core.validatorExists(user1));
        (bytes32 retrievedHash, bool exists) = core.getValidatorInfo(user1);
        assertEq(retrievedHash, publicKeyHash);
        assertTrue(exists);

        vm.stopPrank();
    }

    function test_CreateValidator_RevertAlreadyExists() public {
        vm.startPrank(address(multisig));

        bytes32 publicKeyHash = keccak256("validator_key");

        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__ValidatorAlreadyExists.selector
        );
        core.createValidator(publicKeyHash, validator1); // validator1 already exists from genesis

        vm.stopPrank();
    }

    function test_DeactivateValidator() public {
        vm.startPrank(address(multisig));

        vm.expectEmit(true, false, false, false);
        emit ValidatorUnlockInitiated(validator1, uint64(block.timestamp));

        core.deactivateValidator(validator1);

        vm.stopPrank();
    }

    function test_CompleteValidatorUnlock() public {
        vm.startPrank(address(multisig));

        // First deactivate
        core.deactivateValidator(validator1);

        // Fast forward time
        vm.warp(block.timestamp + 15 days);

        vm.expectEmit(true, false, false, false);
        emit ValidatorUnlocked(validator1);

        core.completeValidatorUnlock(validator1);

        vm.stopPrank();
    }

    function test_CompleteValidatorUnlock_RevertTooEarly() public {
        vm.startPrank(address(multisig));

        core.deactivateValidator(validator1);

        // Don't fast forward time enough
        vm.warp(block.timestamp + 10 days);

        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__UnlockPeriodNotComplete.selector
        );
        core.completeValidatorUnlock(validator1);

        vm.stopPrank();
    }

    function test_AddNetwork() public {
        vm.startPrank(address(token));

        core.addNetwork("Bitcoin Network");

        (uint8 id, bool exists, string memory name) = core.getNetworkInfo(0);
        assertEq(id, 0);
        assertTrue(exists);
        assertEq(name, "Bitcoin Network");

        vm.stopPrank();
    }

    function test_UpdateContract() public {
        // Setup: create jobs and network
        vm.startPrank(address(token));
        core.addNetwork("Test Network");
        vm.stopPrank();

        vm.startPrank(validator1);
        token.transfer(user1, 10000e18);
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(core), 2000e18);

        bytes32 jobId1 = keccak256("job1");
        bytes32 jobId2 = keccak256("job2");
        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        core.requestJob(jobId1, 0, capacities, 1000e18);
        core.requestJob(jobId2, 0, capacities, 1000e18);
        vm.stopPrank();

        // Update contract
        vm.startPrank(address(multisig));

        bytes32[] memory jobHashes = new bytes32[](2);
        jobHashes[0] = jobId1;
        jobHashes[1] = jobId2;

        address[] memory workers = new address[](2);
        workers[0] = worker1;
        workers[1] = worker2;

        uint256[] memory workerCapacities = new uint256[](2);
        workerCapacities[0] = 100;
        workerCapacities[1] = 200;

        address[] memory validatorsVoted = new address[](2);
        validatorsVoted[0] = validator1;
        validatorsVoted[1] = validator2;

        core.updateContract(
            jobHashes,
            workers,
            workerCapacities,
            validatorsVoted
        );

        // Jobs should be deleted
        (, , , bool exists1) = core.getJobInfo(jobId1);
        (, , , bool exists2) = core.getJobInfo(jobId2);
        assertFalse(exists1);
        assertFalse(exists2);

        vm.stopPrank();
    }

    function test_UpdateContract_RevertInvalidArrayLength() public {
        vm.startPrank(address(multisig));

        bytes32[] memory jobHashes = new bytes32[](0);
        address[] memory workers = new address[](2);
        uint256[] memory capacities = new uint256[](1); // Mismatched length
        address[] memory validators = new address[](1);

        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__InvalidArrayLength.selector
        );
        core.updateContract(jobHashes, workers, capacities, validators);

        vm.stopPrank();
    }

    // ============ Integration Tests =============

    function test_FullJobLifecycle() public {
        // Setup network
        vm.startPrank(address(token));
        core.addNetwork("Full Test Network");
        vm.stopPrank();

        // Give user tokens
        vm.startPrank(validator1);
        token.transfer(user1, 10000e18);
        vm.stopPrank();

        // Request job
        vm.startPrank(user1);
        token.approve(address(core), 1000e18);

        bytes32 jobId = keccak256("full_lifecycle_job");
        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        uint256 balanceBefore = token.balanceOf(user1);
        core.requestJob(jobId, 0, capacities, 1000e18);

        // Balance should decrease due to escrow
        assertEq(token.balanceOf(user1), balanceBefore - 1000e18);
        vm.stopPrank();

        // Complete job via multisig
        vm.startPrank(address(multisig));

        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = jobId;

        address[] memory workers = new address[](1);
        workers[0] = worker1;

        uint256[] memory workerCapacities = new uint256[](1);
        workerCapacities[0] = 100;

        address[] memory validatorsVoted = new address[](1);
        validatorsVoted[0] = validator1;

        core.updateContract(
            jobHashes,
            workers,
            workerCapacities,
            validatorsVoted
        );

        vm.stopPrank();

        // Worker should be able to claim rewards
        vm.startPrank(worker1);
        uint256 workerBalanceBefore = token.balanceOf(worker1);
        token.claimRewards();
        assertGt(token.balanceOf(worker1), workerBalanceBefore);
        vm.stopPrank();

        // Validator should be able to claim rewards
        vm.startPrank(validator1);
        uint256 validatorBalanceBefore = token.balanceOf(validator1);
        token.claimRewards();
        assertGt(token.balanceOf(validator1), validatorBalanceBefore);
        vm.stopPrank();
    }

    // ============ Fuzz Tests =============

    function testFuzz_EmissionRate(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 0, 365 days * 50); // Test up to 50 years

        vm.warp(block.timestamp + timeOffset);
        uint256 emission = token.getEmissionRate();

        // Emission should never be less than tail emission
        assertGe(emission, TAIL_EMISSION);

        // Emission should never exceed initial emission
        assertLe(emission, INITIAL_EMISSION_RATE);
    }

    function testFuzz_EscrowPayment(uint256 amount) public {
        amount = bound(amount, 1, LOCK_AMOUNT);

        vm.startPrank(validator1);
        token.transfer(user1, amount);
        vm.stopPrank();

        vm.startPrank(address(mockCore));
        token.escrowPayment(user1, amount, 1);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(address(token)), amount);

        vm.stopPrank();
    }

    function testFuzz_ValidatorCreation(
        bytes32 publicKeyHash,
        address validatorAddr
    ) public {
        vm.assume(validatorAddr != address(0));
        vm.assume(validatorAddr != validator1);
        vm.assume(validatorAddr != validator2);

        vm.startPrank(address(multisig));

        core.createValidator(publicKeyHash, validatorAddr);

        assertTrue(core.validatorExists(validatorAddr));
        (bytes32 retrievedHash, bool exists) = core.getValidatorInfo(
            validatorAddr
        );
        assertEq(retrievedHash, publicKeyHash);
        assertTrue(exists);

        vm.stopPrank();
    }

    // ============ Edge Cases & Security Tests =============

    function test_ReentrancyProtection() public {
        // Test that functions with nonReentrant modifier cannot be reentered
        // This is a basic test - in a real scenario you'd use a malicious contract
        vm.startPrank(address(mockCore));

        vm.startPrank(validator1);
        token.transfer(user1, 1000e18);
        vm.stopPrank();

        vm.startPrank(address(mockCore));
        token.escrowPayment(user1, 500e18, 1);
        // The function should complete successfully
        assertEq(token.balanceOf(address(token)), 500e18);

        vm.stopPrank();
    }

    function test_AccessControl() public {
        // Test that only authorized addresses can call restricted functions

        // Non-core address trying to call core-only functions on token
        vm.startPrank(user1);
        vm.expectRevert(
            SmartnodesToken.SmartnodesToken__InvalidCaller.selector
        );
        token.escrowPayment(user1, 100e18, 1);
        vm.stopPrank();

        // Non-multisig address trying to call multisig-only functions on core
        vm.startPrank(user1);
        vm.expectRevert(
            SmartnodesCore.SmartnodesCore__NotValidatorContract.selector
        );
        core.createValidator(bytes32(0), user2);
        vm.stopPrank();
    }

    function test_ZeroAddressValidation() public {
        vm.startPrank(address(mockCore));

        vm.expectRevert(SmartnodesToken.SmartnodesToken__ZeroAddress.selector);
        token.escrowPayment(address(0), 100e18, 1);

        vm.expectRevert(SmartnodesToken.SmartnodesToken__ZeroAddress.selector);
        token.releaseEscrow(address(0), 100e18);

        vm.expectRevert(SmartnodesToken.SmartnodesToken__ZeroAddress.selector);
        token.createValidatorLock(address(0));

        vm.stopPrank();
    }

    // Helper functions for testing
    function _createTestJob(
        address requester,
        uint128 payment
    ) internal returns (bytes32) {
        bytes32 jobId = keccak256(
            abi.encodePacked(requester, payment, block.timestamp)
        );

        vm.startPrank(validator1);
        token.transfer(requester, payment * 2);
        vm.stopPrank();

        vm.startPrank(requester);
        token.approve(address(core), payment);

        uint64[] memory capacities = new uint64[](1);
        capacities[0] = 100;

        core.requestJob(jobId, 0, capacities, payment);
        vm.stopPrank();

        return jobId;
    }
}

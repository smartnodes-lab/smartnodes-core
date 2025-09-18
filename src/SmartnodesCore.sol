// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ISmartnodesCoordinator} from "./interfaces/ISmartnodesCoordinator.sol";
import {ISmartnodesERC20, PaymentAmounts} from "./interfaces/ISmartnodesERC20.sol";

/**
 * @title SmartnodesCore - Job Management System for Secure, Incentivised, Multi-Network P2P Resource Sharing
 * @dev Optimized core contract for managing multiple networks, jobs, validators, and rewards
 * @dev Supports both SNO token and ETH payments
 */
contract SmartnodesCore {
    // ============= Errors ==============
    error Core__InvalidUser();
    error Core__InvalidPayment();
    error Core__InvalidArrayLength();
    error Core__InsufficientBalance();
    error Core__JobExists();
    error Core__NotValidatorMultisig();
    error Core__NotToken();
    error Core__NodeExists();

    // ============= Events ==============
    enum JobState {
        DoesntExist,
        Pending,
        Active,
        Complete
    }

    enum PaymentType {
        SNO_TOKEN,
        ETH
    }

    /** Structs */
    struct Node {
        // Node can be a user or validator
        bytes32 publicKeyHash;
        bool locked;
        bool exists;
    }

    struct Job {
        address owner;
        uint80 payment;
        uint16 packedData; // (state + payWithSNO)
    }

    struct Network {
        string name;
        bool exists;
    }

    /** Constants */
    uint24 private constant UNLOCK_PERIOD = 14 days;

    ISmartnodesERC20 private immutable i_tokenContract;

    /** State Variables */
    ISmartnodesCoordinator private validatorContract;

    uint256 internal jobCounter;

    mapping(address => Node) public validators;
    mapping(address => Node) public users;
    mapping(bytes32 => Job) public jobs;

    /** Events */
    event JobCompleted(bytes32 indexed jobId, uint128 payment, bool payWithSNO);
    event JobCreated(
        bytes32 indexed jobId,
        bytes32 indexed owner,
        string network,
        uint128 payment,
        bool payWithSNO
    );

    modifier onlyCoordinator() {
        if (msg.sender != address(validatorContract))
            revert Core__NotValidatorMultisig();
        _;
    }

    constructor(address _tokenContract) {
        i_tokenContract = ISmartnodesERC20(_tokenContract);
        jobCounter = 0;
    }

    function setCoordinator(address _validatorContract) external {
        if (address(validatorContract) == address(0)) {
            validatorContract = ISmartnodesCoordinator(_validatorContract);
        }
    }

    // ============= Core Functions =============

    /**
     * @notice Creates a new validator in the system
     * @param publicKeyHash Hash of the validator's public key
     */
    function createValidator(bytes32 publicKeyHash) external {
        address validatorAddress = msg.sender;
        Node storage validator = validators[validatorAddress];

        if (validator.exists) revert Core__NodeExists();

        validator.publicKeyHash = publicKeyHash;
        validator.locked = true;
        validator.exists = true;

        // Lock tokens for the validator
        i_tokenContract.lockTokens(validatorAddress, true);
    }

    function createUser(bytes32 publicKeyHash) external {
        address userAddress = msg.sender;
        Node storage user = users[userAddress];

        if (user.exists) revert Core__NodeExists();

        user.publicKeyHash = publicKeyHash;
        user.locked = true;
        user.exists = true;

        // Lock tokens for the user
        i_tokenContract.lockTokens(userAddress, false);
    }

    /**
     * @notice Requests a new job to be created with a form of payment
     * @param _userId Unique identifier associated with P2P node for the requesting user
     * @param _jobId Unique identifier for the job
     * @param _network Network name (for off-chain validators)
     * @param _capacities Array of capacities for the job
     * @param _payment Payment amount for the job in SNO tokens (0 if paying with ETH)
     */
    function requestJob(
        bytes32 _userId,
        bytes32 _jobId,
        string calldata _network,
        uint256[] calldata _capacities,
        uint128 _payment
    ) external payable {
        if (_capacities.length == 0) {
            revert Core__InvalidArrayLength();
        }

        Job storage job = jobs[_jobId];
        Node storage user = users[msg.sender];

        if (job.owner != address(0)) {
            revert Core__JobExists();
        }

        if (!user.exists) {
            revert Core__InvalidUser();
        }

        // Determine payment type and amount
        bool payWithSNO;
        uint128 finalPayment;

        if (_payment > 0 && msg.value > 0) {
            revert Core__InvalidPayment(); // Can't pay with both
        }

        if (msg.value > 0) {
            finalPayment = uint128(msg.value);
            payWithSNO = false;
        } else if (_payment > 0) {
            finalPayment = _payment;
            payWithSNO = true;
        } else {
            revert Core__InvalidPayment();
        }

        job.owner = msg.sender;
        job.payment = uint80(finalPayment);
        job.packedData = _packJobData(uint8(JobState.Pending), payWithSNO);

        // Handle escrow based on payment type
        if (!payWithSNO) {
            i_tokenContract.escrowEthPayment{value: msg.value}(
                msg.sender,
                finalPayment
            );
        } else {
            i_tokenContract.escrowPayment(msg.sender, finalPayment);
        }

        emit JobCreated(_jobId, _userId, _network, finalPayment, payWithSNO);
    }

    /**
     * @notice Updates contract with completed jobs, and triggers reward distribution
     * @dev Only callable by validator multisig
     */
    function updateContract(
        bytes32[] calldata _jobIds,
        bytes32 _merkleRoot,
        uint256 _totalCapacity,
        address[] memory _approvedValidators,
        address _biasValidator
    ) external onlyCoordinator {
        // Get any job payments associated with reward
        PaymentAmounts memory additionalRewards = _processCompletedJobs(
            _jobIds
        );

        i_tokenContract.createMerkleDistribution(
            _merkleRoot,
            _totalCapacity,
            _approvedValidators,
            additionalRewards,
            _biasValidator
        );
    }

    /**
     * @notice Processes completed jobs and returns any associated payments with job
     * @param _jobIds Array of job IDs that are being completed
     * @return additionalRewards -> total rewards to be distributed from payed jobs
     */
    function _processCompletedJobs(
        bytes32[] calldata _jobIds
    ) internal returns (PaymentAmounts memory additionalRewards) {
        uint256 jobIdsLength = _jobIds.length;

        for (uint256 i = 0; i < jobIdsLength; ) {
            bytes32 jobId = _jobIds[i];
            Job storage job = jobs[jobId];

            uint80 payment = job.payment;
            bool payWithSNO = _unpackPayWithSNO(job.packedData);
            address owner = job.owner;

            if (job.owner != address(0)) {
                // Accumulate rewards by type in single struct
                if (!payWithSNO) {
                    additionalRewards.eth += payment;
                    i_tokenContract.releaseEscrowedEthPayment(owner, payment);
                } else {
                    additionalRewards.sno += payment;
                    i_tokenContract.releaseEscrowedPayment(owner, payment);
                }

                delete jobs[jobId];

                emit JobCompleted(jobId, payment, payWithSNO);
            }

            unchecked {
                ++i;
            }
        }
    }

    // Helper functions for bit manipulation
    function _packJobData(
        uint8 state,
        bool payWithSNO
    ) internal pure returns (uint16) {
        return (uint16(state) << 8) | (payWithSNO ? (1 << 10) : 0);
    }

    function _unpackState(uint16 packedData) internal pure returns (uint8) {
        return uint8((packedData >> 8) & 0x3);
    }

    function _unpackPayWithSNO(uint16 packedData) internal pure returns (bool) {
        return (packedData & (1 << 10)) != 0;
    }

    // ============= VIEW FUNCTIONS =============
    function unpackState(uint16 packedData) public pure returns (uint8) {
        return _unpackState(packedData);
    }

    function unpackPayWithSNO(uint16 packedData) public pure returns (bool) {
        return _unpackPayWithSNO(packedData);
    }

    function getValidatorInfo(
        address _validator
    ) external view returns (bool, bytes32) {
        Node storage validator = validators[_validator];
        return (validator.locked, validator.publicKeyHash);
    }

    function isLockedValidator(address validator) external view returns (bool) {
        return (validators[validator].locked);
    }

    function getCoordinator() external view returns (address) {
        return (address(validatorContract));
    }

    function getJobCount() external view returns (uint256) {
        return (jobCounter);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISmartnodesMultiSig} from "./interfaces/ISmartnodesMultiSig.sol";
import {ISmartnodesToken} from "./interfaces/ISmartnodesToken.sol";

/**
 * @title SmartnodesCore - Optimized Multi-Network Version
 * @dev Optimized core contract for managing multiple networks, jobs, validators, and rewards
 */
contract SmartnodesCore {
    /** Custom errors */
    error SmartnodesCore__ZeroPayment();
    error SmartnodesCore__InvalidNetworkId();
    error SmartnodesCore__InvalidJobId();
    error SmartnodesCore__InsufficientBalance();
    error SmartnodesCore__ValidatorAlreadyExists();
    error SmartnodesCore__ValidatorNotExists();
    error SmartnodesCore__ValidatorNotActive();
    error SmartnodesCore__UnlockPeriodNotComplete();
    error SmartnodesCore__NotValidatorContract();
    error SmartnodesCore__NotTokenContract();
    error SmartnodesCore__JobAlreadyExists();
    error SmartnodesCore__InvalidArrayLength();
    error SmartnodesCore__UnauthorizedJobCancellation();
    error SmartnodesCore__ValidatorAlreadyInactive();
    error SmartnodesCore__ValidatorNotUnlocking();
    error SmartnodesCore__JobNotPending();
    error SmartnodesCore__InvalidJobState();
    error SmartnodesCore__NetworkLimitReached();

    /** Constants */
    uint24 private constant UNLOCK_PERIOD = 14 days;
    uint8 private constant MAX_NETWORKS = 255;

    enum JobState {
        Pending,
        Cancelled
    }
    enum ValidatorState {
        Active,
        Inactive,
        Unlocking
    }

    /** Structs */
    struct Validator {
        bytes32 publicKeyHash;
        uint64 lockTime;
        uint64 unlockTime;
        uint8 state;
        bool exists;
    }

    struct Job {
        uint128 payment;
        address requester;
        uint8 networkId;
        uint8 state;
        uint64[] capacities;
        bool exists;
    }

    struct Network {
        uint8 id;
        bool exists;
        string name;
    }

    /** State Variables */
    ISmartnodesMultiSig private immutable i_validatorContract;
    ISmartnodesToken private immutable i_tokenContract;

    uint256 public jobCounter;
    uint8 public networkCounter;

    /** Mappings */
    mapping(address => Validator) public validators;
    mapping(bytes32 => Job) public jobs;
    mapping(uint8 => Network) public networks;

    /** Events */
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

    event NetworkCreated(
        uint8 indexed networkId,
        address indexed owner,
        string name
    );

    event ValidatorCreated(address indexed validator, bytes32 publicKeyHash);
    event ValidatorUnlockInitiated(
        address indexed validator,
        uint64 unlockTime
    );
    event ValidatorUnlocked(address indexed validator);

    modifier onlyValidatorMultisig() {
        if (msg.sender != address(i_validatorContract))
            revert SmartnodesCore__NotValidatorContract();
        _;
    }

    modifier onlyTokenContract() {
        if (msg.sender != address(i_tokenContract))
            revert SmartnodesCore__NotValidatorContract();
        _;
    }

    constructor(
        address tokenAddress,
        address validatorContract,
        address[] memory genesisNodes
    ) {
        i_validatorContract = ISmartnodesMultiSig(validatorContract);
        i_tokenContract = ISmartnodesToken(tokenAddress);

        jobCounter = 0;
        networkCounter = 0;

        for (uint256 i = 0; i < genesisNodes.length; ) {
            address validator = genesisNodes[i];
            if (validator != address(0)) {
                validators[validator] = Validator({
                    publicKeyHash: bytes32(0),
                    lockTime: uint64(block.timestamp),
                    unlockTime: 0,
                    state: uint8(ValidatorState.Active),
                    exists: true
                });
            }
            unchecked {
                ++i;
            }
        }
    }

    // ============ Job-related Functions =============

    /**
     * @notice Requests a new job on a specific network
     * @param jobId Unique identifier for the job
     * @param networkId ID of the network where the job will be executed
     * @param capacities Array of capacities required for the job
     * @param payment Amount of tokens to be paid for the job
     */
    function requestJob(
        bytes32 jobId,
        uint8 networkId,
        uint64[] calldata capacities,
        uint128 payment
    ) external {
        if (payment == 0) revert SmartnodesCore__ZeroPayment();
        if (!networks[networkId].exists)
            revert SmartnodesCore__InvalidNetworkId();
        if (jobs[jobId].networkId != 0)
            revert SmartnodesCore__JobAlreadyExists();
        if (capacities.length == 0) revert SmartnodesCore__InvalidArrayLength();

        // Escrow payment through token contract
        i_tokenContract.escrowPayment(msg.sender, payment, networkId);

        jobs[jobId] = Job({
            payment: payment,
            requester: msg.sender,
            networkId: networkId,
            state: uint8(JobState.Pending),
            capacities: capacities,
            exists: true
        });

        emit JobCreated(jobId, networkId, msg.sender, payment);
    }

    /**
     * @notice Cancel a job and refund the payment
     * @param jobId Unique identifier for the job to be cancelled
     */
    function cancelJob(bytes32 jobId) external {
        Job memory job = jobs[jobId];

        if (job.requester != msg.sender)
            revert SmartnodesCore__UnauthorizedJobCancellation();
        if (job.state != uint8(JobState.Pending))
            revert SmartnodesCore__JobNotPending();

        uint128 payment = job.payment;
        uint8 networkId = job.networkId;

        delete jobs[jobId];

        // Release escrowed payment back to requester
        i_tokenContract.releaseEscrow(msg.sender, payment);

        emit JobCancelled(jobId, networkId, msg.sender);
    }

    /**
     * @notice Completes a job and returns the payment associated with it
     * @param jobId Unique identifier for the job to be completed
     * @return totalReward The payment amount for the completed job
     * @dev Only callable by the validator multisig contract
     */
    function completeJob(
        bytes32 jobId
    ) external onlyValidatorMultisig returns (uint256 totalReward) {
        Job storage job = jobs[jobId];
        if (job.state != uint8(JobState.Pending))
            revert SmartnodesCore__InvalidJobState();

        totalReward = job.payment;
        uint8 networkId = job.networkId;
        address requester = job.requester;

        delete jobs[jobId];

        emit JobCompleted(jobId, networkId, requester);
    }

    // ============ Validator Functions =============

    /**
     * @notice Creates a new validator in the system
     * @param publicKeyHash Hash of the validator's public key
     * @param validatorAddress Address of the validator to be created
     * @dev Only callable by the validator multisig contract
     */
    function createValidator(
        bytes32 publicKeyHash,
        address validatorAddress
    ) external onlyValidatorMultisig {
        if (validatorAddress == address(0))
            revert SmartnodesCore__ZeroPayment();
        if (validators[validatorAddress].exists)
            revert SmartnodesCore__ValidatorAlreadyExists();

        validators[validatorAddress] = Validator({
            publicKeyHash: publicKeyHash,
            lockTime: uint64(block.timestamp),
            unlockTime: 0,
            state: uint8(ValidatorState.Active),
            exists: true
        });

        // Lock tokens for the validator
        i_tokenContract.createValidatorLock(validatorAddress);

        emit ValidatorCreated(validatorAddress, publicKeyHash);
    }

    /**
     * @notice Deactivates a validator and initiates an unlock
     * @param validatorAddress Address of the validator to be removed
     * @dev Only callable by the validator multisig contract
     */
    function deactivateValidator(
        address validatorAddress
    ) external onlyValidatorMultisig {
        Validator storage validator = validators[validatorAddress];

        if (!validator.exists) revert SmartnodesCore__ValidatorAlreadyExists();
        if (validator.state != uint8(ValidatorState.Active))
            revert SmartnodesCore__ValidatorAlreadyInactive();

        validator.state = uint8(ValidatorState.Unlocking);
        validator.unlockTime = uint64(block.timestamp);

        emit ValidatorUnlockInitiated(validatorAddress, validator.unlockTime);
    }

    function completeValidatorUnlock(
        address validatorAddress
    ) external onlyValidatorMultisig {
        Validator storage validator = validators[validatorAddress];

        if (!validator.exists) revert SmartnodesCore__ValidatorNotExists();
        if (validator.state != uint8(ValidatorState.Unlocking))
            revert SmartnodesCore__ValidatorNotUnlocking();
        if (block.timestamp < validator.unlockTime + UNLOCK_PERIOD)
            revert SmartnodesCore__UnlockPeriodNotComplete();

        // Unlock validator tokens
        validator.state = uint8(ValidatorState.Inactive);
        validator.exists = true;
        validator.unlockTime = 0;

        i_tokenContract.unlockValidatorTokens(validatorAddress);

        emit ValidatorUnlocked(validatorAddress);
    }

    /**
     * @notice Add a new network to the system
     * @param name Name of the network
     */
    function addNetwork(string calldata name) external onlyTokenContract {
        if (networkCounter >= MAX_NETWORKS)
            revert SmartnodesCore__InvalidNetworkId();

        uint8 networkId = networkCounter;
        unchecked {
            networkCounter++;
        }

        networks[networkId] = Network({
            id: networkId,
            exists: true,
            name: name
        });

        emit NetworkCreated(networkId, msg.sender, name);
    }

    /**
     * @notice Update contract state and distribute rewards
     * @param jobHashes Array of completed job IDs
     * @param workers Array of worker addresses
     * @param capacities Array of worker capacities
     * @param validatorsVoted Array of validators who participated
     */
    function updateContract(
        bytes32[] calldata jobHashes,
        address[] calldata workers,
        uint256[] calldata capacities,
        address[] calldata validatorsVoted
    ) external onlyValidatorMultisig {
        uint256 workersLength = workers.length;
        uint256 capacitiesLength = capacities.length;
        uint256 jobsLength = jobHashes.length;
        uint256 validatorsLength = validatorsVoted.length;

        if (workersLength != capacitiesLength)
            revert SmartnodesCore__InvalidArrayLength();

        // Process completed jobs
        uint256 additionalReward = 0;
        for (uint256 i = 0; i < jobsLength; ) {
            bytes32 jobId = jobHashes[i];
            Job storage job = jobs[jobId];

            if (!job.exists) revert SmartnodesCore__InvalidJobId();
            if (job.state != uint8(JobState.Pending))
                revert SmartnodesCore__InvalidJobState();

            additionalReward += job.payment;
            delete jobs[jobId];

            emit JobCompleted(jobId, job.networkId, job.requester);

            unchecked {
                ++i;
            }
        }

        // Distribute rewards through token contract
        i_tokenContract.mintRewards(
            workers,
            validatorsVoted,
            capacities,
            additionalReward
        );
    }

    // ============ View Functions =============

    /**
     * @notice Check if a validator exists
     * @param validatorAddress Address to check
     * @return exists Whether the validator exists
     */
    function validatorExists(
        address validatorAddress
    ) external view returns (bool exists) {
        exists = validators[validatorAddress].exists;
    }

    /**
     * @notice Get validator information
     * @param validatorAddress Address of the validator
     * @return publicKeyHash The validator's public key hash
     * @return exists Whether the validator exists
     */
    function getValidatorInfo(
        address validatorAddress
    ) external view returns (bytes32 publicKeyHash, bool exists) {
        Validator memory validator = validators[validatorAddress];
        return (validator.publicKeyHash, validator.exists);
    }

    /**
     * @notice Get job information
     * @param jobId ID of the job
     * @return payment Payment amount
     * @return requester Address of job requester
     * @return networkId Network ID
     * @return exists Whether the job exists
     */
    function getJobInfo(
        bytes32 jobId
    )
        external
        view
        returns (
            uint128 payment,
            address requester,
            uint8 networkId,
            bool exists
        )
    {
        Job memory job = jobs[jobId];
        return (job.payment, job.requester, job.networkId, job.exists);
    }

    /**
     * @notice Get network information
     * @param networkId ID of the network
     * @return id Network ID
     * @return exists Whether the network exists
     * @return name Network name
     */
    function getNetworkInfo(
        uint8 networkId
    ) external view returns (uint8 id, bool exists, string memory name) {
        Network memory network = networks[networkId];
        return (network.id, network.exists, network.name);
    }
}

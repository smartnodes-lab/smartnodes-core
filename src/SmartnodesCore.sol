// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// import {ISmartnodesCoordinator} from "./interfaces/ISmartnodesCoordinator.sol";
import {ISmartnodesToken} from "./interfaces/ISmartnodesToken.sol";

/**
 * @title SmartnodesCore - Job Management System for Secure, Incentivised, Multi-Network P2P Resource Sharing
 * @dev Optimized core contract for managing multiple networks, jobs, validators, and rewards
 * @dev Supports both SNO token and ETH payments
 */
contract SmartnodesCore {
    /** Errors */
    error SmartnodesCore__InvalidNetworkId();
    error SmartnodesCore__InvalidUser();
    error SmartnodesCore__InvalidPayment();
    error SmartnodesCore__InvalidArrayLength();
    error SmartnodesCore__InsufficientBalance();
    error SmartnodesCore__JobExists();
    error SmartnodesCore__NotValidatorMultisig();
    error SmartnodesCore__NodeExists();

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
    struct Validator {
        bytes32 publicKeyHash;
        uint8 reputation;
        bool active;
        bool exists;
    }

    struct User {
        bytes32 publicKeyHash;
        uint8 reputation;
        bool exists;
    }

    struct Job {
        uint128 payment;
        uint8 networkId;
        uint8 state;
        uint8 paymentType;
        address owner;
    }

    struct Network {
        uint8 networkId;
        bool exists;
        string name;
    }

    /** Constants */
    uint24 private constant UNLOCK_PERIOD = 14 days;
    uint8 private constant MAX_NETWORKS = 16;

    // ISmartnodesCoordinator private immutable i_validatorContract;
    ISmartnodesToken private immutable i_tokenContract;

    /** State Variables */
    uint256 public jobCounter;
    uint8 public networkCounter;

    mapping(address => Validator) public validators;
    mapping(address => User) public users;
    mapping(bytes32 => Job) public jobs;
    mapping(uint8 => Network) public networks;

    /** Events */
    event JobCompleted(
        bytes32 indexed jobId,
        uint8 networkId,
        uint128 payment,
        uint8 paymentType
    );
    event JobCreated(
        bytes32 indexed jobId,
        address indexed owner,
        uint8 networkId,
        uint128 payment,
        uint8 paymentType
    );
    event NetworkAdded(uint8 indexed networkId, string name);
    event NetworkRemoved(uint8 indexed networkId);

    // modifier onlyCoordinator() {
    //     if (msg.sender != address(i_validatorContract))
    //         revert SmartnodesCore__NotValidatorMultisig();
    //     _;
    // }

    constructor(address _tokenContract) {
        // i_validatorContract = ISmartnodesCoordinator(_validatorContract);
        i_tokenContract = ISmartnodesToken(_tokenContract);

        jobCounter = 0;
        networkCounter = 0;
    }

    // ============= Core Functions =============
    /**
     * @notice Add a new network to the system
     * @param _name Name of the network
     */
    function addNetwork(string calldata _name) external {
        if (networkCounter >= MAX_NETWORKS)
            revert SmartnodesCore__InvalidNetworkId();

        uint8 newNetworkId = ++networkCounter;
        networks[newNetworkId] = Network({
            networkId: newNetworkId,
            exists: true,
            name: _name
        });

        emit NetworkAdded(newNetworkId, _name);
    }

    /**
     * @notice Remove network from the system
     * @param _networkId network id
     */
    function removeNetwork(uint8 _networkId) external {
        Network storage network = networks[_networkId];

        if (!network.exists) revert SmartnodesCore__InvalidNetworkId();

        delete networks[_networkId];

        emit NetworkRemoved(_networkId);
    }

    /**
     * @notice Creates a new validator in the system
     * @param publicKeyHash Hash of the validator's public key
     */
    function createValidator(bytes32 publicKeyHash) external {
        address validatorAddress = msg.sender;
        Validator storage validator = validators[validatorAddress];

        if (validator.exists) revert SmartnodesCore__NodeExists();

        validator.publicKeyHash = publicKeyHash;
        validator.active = false;
        validator.exists = true;

        // Lock tokens for the validator
        i_tokenContract.lockTokens(validatorAddress, 1);
    }

    function createUser(bytes32 publicKeyHash) external {
        address userAddress = msg.sender;
        User storage user = users[userAddress];

        if (user.exists) revert SmartnodesCore__NodeExists();

        user.publicKeyHash = publicKeyHash;
        user.reputation = 1;
        user.exists = true;
    }

    /**
     * @notice Requests a new job to be created
     * @param _userId Unique identifier associated with P2P node for the requesting user
     * @param _networkId ID of the network where the job will be executed
     * @param _capacities Array of capacities for the job (not used in this implementation)
     * @param _payment Payment amount for the job in SNO tokens (0 if paying with ETH)
     */
    function requestJob(
        bytes32 _userId,
        bytes32 _jobId,
        uint8 _networkId,
        uint256[] calldata _capacities,
        uint128 _payment
    ) external payable {
        if (_networkId >= networkCounter || _networkId == 0) {
            revert SmartnodesCore__InvalidNetworkId();
        }
        if (_capacities.length == 0) {
            revert SmartnodesCore__InvalidArrayLength();
        }

        Job storage job = jobs[_jobId];
        User storage user = users[msg.sender]; // Fixed: should use msg.sender, not _userId

        if (job.owner != address(0)) {
            revert SmartnodesCore__JobExists();
        }

        if (!user.exists || user.reputation == 0) {
            // Fixed: check if user exists
            revert SmartnodesCore__InvalidUser();
        }

        // Determine payment type and amount
        uint8 paymentType;
        uint128 finalPayment;

        if (_payment > 0 && msg.value > 0) {
            revert SmartnodesCore__InvalidPayment(); // Can't pay with both
        }

        if (msg.value > 0) {
            finalPayment = uint128(msg.value);
            paymentType = uint8(PaymentType.ETH);
        } else if (_payment > 0) {
            finalPayment = _payment;
            paymentType = uint8(PaymentType.SNO_TOKEN);
        } else {
            revert SmartnodesCore__InvalidPayment();
        }

        job.payment = finalPayment;
        job.owner = msg.sender;
        job.networkId = _networkId;
        job.state = uint8(JobState.Pending);
        job.paymentType = paymentType;

        // Handle escrow based on payment type
        if (paymentType == uint8(PaymentType.ETH)) {
            i_tokenContract.escrowEthPayment{value: msg.value}(
                msg.sender,
                finalPayment,
                _networkId
            );
        } else {
            i_tokenContract.escrowPayment(msg.sender, finalPayment, _networkId);
        }

        emit JobCreated(
            _jobId,
            msg.sender,
            _networkId,
            finalPayment,
            paymentType
        );
    }

    /**
     * @notice Updates contract with completed jobs, and triggers reward distribution
     */
    function updateContract(
        bytes32[] calldata _jobIds,
        address[] calldata _validators,
        address[] calldata _workers,
        uint256[] calldata _capacities
    ) external {
        uint256 workersLength = _workers.length;
        uint256 capacitiesLength = _capacities.length;
        if (workersLength != capacitiesLength || _validators.length == 0) {
            revert SmartnodesCore__InvalidArrayLength();
        }

        // Get any job payments associated with reward
        (
            uint256 additionalReward,
            uint256 additionalEthReward
        ) = _processCompletedJobs(_jobIds);

        i_tokenContract.mintRewards(
            _validators,
            _workers,
            _capacities,
            additionalReward,
            additionalEthReward
        );
    }

    /**
     * @notice Processes completed jobs and returns any associated payments with job
     * @param _jobIds Array of job IDs that are being completed
     * @return additionalReward Total additional reward to be distributed
     * @return additionalEthReward Total additional ETH reward to be distributed
     */
    function _processCompletedJobs(
        bytes32[] calldata _jobIds
    ) internal returns (uint256 additionalReward, uint256 additionalEthReward) {
        // Mark each job as complete, and get their associated payment
        uint256 jobIdsLength = _jobIds.length;

        for (uint256 i = 0; i < jobIdsLength; ) {
            bytes32 jobId = _jobIds[i];
            Job storage job = jobs[jobId]; // Use storage to modify

            uint128 payment = job.payment;
            uint8 paymentType = job.paymentType;
            uint8 networkId = job.networkId;
            address owner = job.owner;

            // If this was a job listed on contract, accumulate the payment and emit event
            if (job.networkId > 0) {
                if (paymentType == uint8(PaymentType.ETH)) {
                    additionalEthReward += payment;
                    // Release escrowed ETH payment for reward distribution
                    i_tokenContract.releaseEscrowedEthPayment(owner, payment);
                } else {
                    additionalReward += payment;
                    // Release escrowed token payment for reward distribution
                    i_tokenContract.releaseEscrowedPayment(owner, payment);
                }

                // Mark job as complete and clear storage
                job.state = uint8(JobState.Complete);
                delete jobs[jobId];

                emit JobCompleted(jobId, networkId, payment, paymentType);
            }

            unchecked {
                ++i;
            }
        }
    }
}

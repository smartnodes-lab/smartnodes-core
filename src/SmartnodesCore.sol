// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ISmartnodesCoordinator} from "./interfaces/ISmartnodesCoordinator.sol";
import {ISmartnodesToken, PaymentAmounts} from "./interfaces/ISmartnodesToken.sol";

/**
 * @title SmartnodesCore - Job Management System for Secure, Incentivised, Multi-Network P2P Resource Sharing
 * @dev Optimized core contract for managing multiple networks, jobs, validators, and rewards
 * @dev Supports both SNO token and ETH payments
 */
contract SmartnodesCore {
    // ============= Errors ==============
    error Core__InvalidNetworkId();
    error Core__InvalidUser();
    error Core__InvalidPayment();
    error Core__InvalidArrayLength();
    error Core__InsufficientBalance();
    error Core__JobExists();
    error Core__NotValidatorMultisig();
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
        // Can be a user or validator
        bytes32 publicKeyHash;
        uint8 reputation;
        bool locked;
        bool exists;
    }

    struct Job {
        uint128 payment;
        uint8 networkId;
        uint8 state;
        bool payWithSNO;
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

    ISmartnodesToken private immutable i_tokenContract;

    /** State Variables */
    ISmartnodesCoordinator private validatorContract;

    uint256 public jobCounter;
    uint8 public networkCounter;

    mapping(address => Node) public validators;
    mapping(address => Node) public users;
    mapping(bytes32 => Job) public jobs;
    mapping(uint8 => Network) public networks;

    /** Events */
    event JobCompleted(
        bytes32 indexed jobId,
        uint8 networkId,
        uint128 payment,
        bool payWithSNO
    );
    event JobCreated(
        bytes32 indexed jobId,
        bytes32 indexed owner,
        uint8 networkId,
        uint128 payment,
        bool payWithSNO
    );
    event NetworkAdded(uint8 indexed networkId, string name);
    event NetworkRemoved(uint8 indexed networkId);

    modifier onlyCoordinator() {
        if (msg.sender != address(validatorContract))
            revert Core__NotValidatorMultisig();
        _;
    }

    constructor(address _tokenContract) {
        i_tokenContract = ISmartnodesToken(_tokenContract);

        jobCounter = 0;
        networkCounter = 0;
    }

    function setCoordinator(address _validatorContract) external {
        if (address(validatorContract) == address(0)) {
            validatorContract = ISmartnodesCoordinator(_validatorContract);
        }
    }

    // ============= Core Functions =============
    /**
     * @notice Add a new network to the system
     * @param _name Name of the network
     */
    function addNetwork(string calldata _name) external {
        if (networkCounter >= MAX_NETWORKS) revert Core__InvalidNetworkId();

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

        if (!network.exists) revert Core__InvalidNetworkId();

        delete networks[_networkId];

        emit NetworkRemoved(_networkId);
    }

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
        if (_networkId > networkCounter || _networkId == 0) {
            revert Core__InvalidNetworkId();
        }
        if (_capacities.length == 0) {
            revert Core__InvalidArrayLength();
        }

        Job storage job = jobs[_jobId];
        Node storage user = users[msg.sender]; // Fixed: should use msg.sender, not _userId

        if (job.owner != address(0)) {
            revert Core__JobExists();
        }

        if (!user.exists || user.reputation == 0) {
            // Fixed: check if user exists
            revert Core__InvalidUser();
        }

        // Determine payment type and amount
        bool payWithSNO;
        uint128 finalPayment;

        if (_payment > 0 && msg.value > 0) {
            revert Core__InvalidPayment(); // Can't pay with both?
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

        job.payment = finalPayment;
        job.owner = msg.sender;
        job.networkId = _networkId;
        job.state = uint8(JobState.Pending);
        job.payWithSNO = payWithSNO;

        // Handle escrow based on payment type
        if (!payWithSNO) {
            i_tokenContract.escrowEthPayment{value: msg.value}(
                msg.sender,
                finalPayment,
                _networkId
            );
        } else {
            i_tokenContract.escrowPayment(msg.sender, finalPayment, _networkId);
        }

        emit JobCreated(_jobId, _userId, _networkId, finalPayment, payWithSNO);
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
            revert Core__InvalidArrayLength();
        }

        // Get any job payments associated with reward
        PaymentAmounts memory additionalRewards = _processCompletedJobs(
            _jobIds
        );

        i_tokenContract.mintRewards(
            _validators,
            _workers,
            _capacities,
            additionalRewards
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

            uint128 payment = job.payment;
            bool payWithSNO = job.payWithSNO;
            address owner = job.owner;

            if (job.networkId > 0) {
                // Accumulate rewards by type in single struct
                if (!payWithSNO) {
                    additionalRewards.eth += payment;
                    i_tokenContract.releaseEscrowedEthPayment(owner, payment);
                } else {
                    additionalRewards.sno += payment;
                    i_tokenContract.releaseEscrowedPayment(owner, payment);
                }

                // Cleanup
                job.state = uint8(JobState.Complete);
                delete jobs[jobId];

                emit JobCompleted(jobId, job.networkId, payment, payWithSNO);
            }

            unchecked {
                ++i;
            }
        }
    }

    // ============= VIEW FUNCTIONS =============

    function isLockedValidator(address validator) external view returns (bool) {
        return (validators[validator].locked);
    }

    function getCoordinator() external view returns (address) {
        return (address(validatorContract));
    }
}

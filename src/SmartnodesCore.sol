// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISmartnodesMultiSig} from "./interfaces/ISmartnodesMultiSig.sol";

/** Custom errors */
error SmartnodesCore__InvalidPayment();
error SmartnodesCore__InvalidNetworkId();
error SmartnodesCore__InsufficientBalance();
error SmartnodesCore__ValidatorAlreadyExists();

/**
 * @title SmartnodesCore - Optimized Multi-Network Version
 * @dev Optimized core contract for managing multiple networks, jobs, validators, and rewards
 */
contract SmartnodesCore is ERC20 {
    /** Constants */
    uint128 private constant LOCK_AMOUNT = 500_000e18;
    uint128 private constant INITIAL_EMISSION_RATE = 4096e18;
    uint128 private constant TAIL_EMISSION = 128e18;
    uint24 private constant UNLOCK_PERIOD = 14 days;
    uint16 private constant INITIAL_HALVING_PERIOD = 8742;
    uint16 private constant MAX_NETWORKS = 32767;

    /** Structs */
    struct Validator {
        uint256 tokensLocked;
        uint64 unlockTime;
        bytes32 publicKey;
        bool exists;
    }

    struct Job {
        uint128 payment;
        address requester;
        uint8 networkId;
        bool exists;
    }

    struct Network {
        uint8 id;
        string name;
        address owner;
        bool exists;
    }

    /** State Variables */
    ISmartnodesMultiSig private immutable validatorContract;

    // Emission Rate
    uint128 public emissionRate = INITIAL_EMISSION_RATE;
    uint128 public totalUnclaimedRewards;

    // Mappings
    mapping(address => Validator) public validators;
    mapping(bytes32 => Job) public jobs;
    mapping(uint8 => Network) public networks;
    mapping(address => uint128) public rewards;

    /** Events */
    event JobCreated(
        bytes32 indexed jobId,
        uint8 indexed networkId,
        address indexed requester,
        uint128 payment
    );

    constructor(address[] memory genesisNodes) ERC20("Smartnodes", "SNO") {
        address _validatorContract = 0x1234567890123456789012345678901234567890; // Replace with actual validator contract address
        validatorContract = ISmartnodesMultiSig(_validatorContract);

        for (uint256 i = 0; i < genesisNodes.length; i++) {
            address validator = genesisNodes[i];

            validators[validator] = Validator({
                tokensLocked: LOCK_AMOUNT,
                unlockTime: uint64(block.timestamp + UNLOCK_PERIOD),
                publicKey: bytes32(0), // Placeholder, should be set later
                exists: true
            });
            _mint(validator, LOCK_AMOUNT);
        }
    }

    // function createValidator(bytes32 publicKeyHash) external {
    //     if (balanceOf(msg.sender) < LOCK_AMOUNT)
    //         revert SmartnodesCore__InsufficientBalance();
    // }

    // function createJob(
    //     bytes32 jobId,
    //     uint8 networkId,
    //     uint64[] calldata capacities,
    //     uint128 payment
    // ) external {
    //     if (payment == 0) revert SmartnodesCore__InvalidPayment();
    //     if (networkId == 0 || networkId > MAX_NETWORKS)
    //         revert SmartnodesCore__InvalidNetworkId();
    //     if (jobs[jobId].exists) revert SmartnodesCore__ValidatorAlreadyExists();
    //     if (networks[networkId].exists == false)
    //         revert SmartnodesCore__InvalidNetworkId();

    //     jobs[jobId] = Job({
    //         payment: payment,
    //         requester: msg.sender,
    //         networkId: networkId,
    //         exists: true
    //     });
    //     rewards[msg.sender] += payment;
    //     totalUnclaimedRewards += payment;
    //     emit JobCreated(jobId, networkId, msg.sender, payment);
    // }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SmartnodesToken
 * @dev Manages the Smartnodes ERC20 token with reward claiming, assignment, and reward distribution curve control.
 */
contract SmartnodesToken is ERC20, ReentrancyGuard {
    // Custom Errors
    error SmartnodesCore__ZeroAddress();
    error SmartnodesToken__InvalidCaller();
    error SmartnodesToken__InvalidWorkerData();
    error SmartnodesCore__InvalidPayment();

    struct ValidatorLock {
        uint256 tokensLocked; // Amount of tokens locked by the validator
        uint256 unlockTime; // Timestamp when the tokens can be unlocked
        bool exists; // Whether the validator lock exists
    }

    // Constants
    uint256 private constant VALIDATOR_REWARD_PERCENTAGE = 10;
    uint256 private constant INITIAL_EMISSION_RATE = 5832e18;
    uint256 private constant TAIL_EMISSION = 512e18;
    uint256 private constant TRISECTION_PERIOD = 365 days; // 1 year in seconds
    uint256 private immutable i_DEPLOY_TIME;
    uint96 private immutable i_lockAmount = 250_000e18;

    // State Variables
    address private s_smartnodesCore;
    mapping(address user => uint256 unclaimedRewards)
        private s_unclaimedRewards;
    mapping(address => ValidatorLock) private s_validatorLocks;

    // Modifiers
    modifier onlyCore() {
        // Check if the caller is the SmartnodesCore contract
        if (msg.sender != s_smartnodesCore)
            revert SmartnodesToken__InvalidCaller();
        _;
    }

    // Events
    event SmartnodesToken__PaymentEscrowed(
        address user,
        uint256 payment,
        uint8 networkId
    );

    constructor(
        address[] memory _genesisNodes,
        address _smartnodesCore
    ) ERC20("Smartnodes", "SNO") {
        s_smartnodesCore = _smartnodesCore;
        i_DEPLOY_TIME = block.timestamp;

        // Mint initial tokens to genesis nodes
        for (uint256 i = 0; i < _genesisNodes.length; ) {
            address validator = _genesisNodes[i];
            _mint(validator, i_lockAmount);
            unchecked {
                ++i;
            }
        }
    }

    // ============ Payments & Locking =============

    /**
     * @notice Escrow payment to a user for a job on a specific network
     * @dev Only callable by the SmartnodesCore contract
     * @param _user The address of the user receiving the payment
     * @param _amount The amount of tokens to escrow
     * @param _networkId The ID of the network for which the payment is made
     */
    function escrowPaywment(
        address _user,
        uint256 _amount,
        uint8 _networkId
    ) external onlyCore nonReentrant {
        if (_user == address(0)) {
            revert SmartnodesCore__ZeroAddress();
        }
        if (_amount == 0) {
            revert SmartnodesCore__InvalidPayment();
        }

        // Transfer tokens from the caller to the worker
        _transfer(msg.sender, _user, _amount);

        // Emit event for payment escrowed
        emit SmartnodesToken__PaymentEscrowed(_user, _amount, _networkId);
    }

    function releaseEscrow(
        address _user,
        uint256 _amount
    ) external onlyCore nonReentrant {
        if (_user == address(0)) {
            revert SmartnodesCore__ZeroAddress();
        }
        if (_amount == 0) {
            revert SmartnodesCore__InvalidPayment();
        }

        // Transfer tokens from the contract to the user
        _transfer(address(this), _user, _amount);
    }

    // ============ Emissions & Halving ============

    /**
     * @notice Distribute rewards to workers and validators
     * @dev Called by SmartnodesCore during state updates
     */
    function mintRewards(
        address[] calldata _workers,
        address[] calldata _validatorsVoted,
        uint256[] calldata _workerCapacities,
        uint256 additionalReward
    ) external onlyCore nonReentrant {
        if (_workerCapacities.length != _workers.length) {
            revert SmartnodesToken__InvalidWorkerData();
        }
        uint256 currentEmission = getEmissionRate();
        uint256 totalReward = currentEmission + additionalReward;

        uint256 validatorReward;
        uint256 workerReward;
        if (_workers.length == 0) {
            validatorReward = totalReward;
        } else {
            workerReward =
                (totalReward * (100 - VALIDATOR_REWARD_PERCENTAGE)) /
                100;
            validatorReward = totalReward - workerReward;
        }

        // Sum total worker capacity
        uint256 totalWorkerCapacity;
        for (uint256 i = 0; i < _workerCapacities.length; ) {
            totalWorkerCapacity += _workerCapacities[i];
            unchecked {
                ++i;
            }
        }

        // Distribute validator rewards equally
        if (_validatorsVoted.length > 0) {
            uint256 validatorShare = validatorReward / _validatorsVoted.length;
            for (uint256 i = 0; i < _validatorsVoted.length; ) {
                s_unclaimedRewards[_validatorsVoted[i]] += validatorShare;
                unchecked {
                    ++i;
                }
            }
        }

        // Distribute worker rewards proportional to their capacities
        if (totalWorkerCapacity > 0) {
            for (uint256 i = 0; i < _workers.length; ) {
                uint256 capacity = _workerCapacities[i];
                s_unclaimedRewards[_workers[i]] +=
                    (workerReward * capacity) /
                    totalWorkerCapacity;
                unchecked {
                    ++i;
                }
            }
        }
    }

    function claimRewards() external nonReentrant {
        uint256 unclaimed = s_unclaimedRewards[msg.sender];
        if (unclaimed == 0) {
            return;
        }

        // Reset unclaimed rewards before transfer to prevent reentrancy
        s_unclaimedRewards[msg.sender] = 0;

        // Mint the claimed rewards
        _mint(msg.sender, unclaimed);
    }

    /**
     * @notice Updates emission rate based on halving schedule
     * @dev Called by SmartnodesCore during state updates
     */
    function updateEmissionRate() external onlyCore {}

    /**
     * @return era 0 for the first era, 1 after the first year, 2 after the second, …
     */
    function _currentEra() internal view returns (uint256 era) {
        unchecked {
            era = (block.timestamp - i_DEPLOY_TIME) / TRISECTION_PERIOD;
        }
    }

    /**
     * @notice Get the current emission rate based on the era
     * @return The current emission rate
     */
    function _emissionForEra(uint256 era) internal pure returns (uint256) {
        if (era == 0) {
            return INITIAL_EMISSION_RATE;
        }

        // Each era is 2/3 of the previous era
        uint256 emission = INITIAL_EMISSION_RATE;
        for (uint256 i = 0; i < era; ) {
            emission = (emission * 2) / 3;
            // Stop diminishing once we reach tail emission
            if (emission <= TAIL_EMISSION) {
                return TAIL_EMISSION;
            }
            unchecked {
                ++i;
            }
        }

        return emission;
    }

    // =========== Getters ============

    /**
     * @notice Get current emission rate based on era
     */
    function getEmissionRate() public view returns (uint256 emissionRate) {
        uint256 era = _currentEra();
        emissionRate = _emissionForEra(era);
    }
}

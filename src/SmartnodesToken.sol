// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";

// import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
// import {ERC20Permit} from "@openzeppelin/contracts/token/ER
// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {Govenor} from "@openzeppelin/contracts/governance/Governor.sol";

/**
 * @title Smartnodes Payment and Governance Token
 * @dev Non-upgradeable ERC20 token for job payments and rewards with governance capabilities for SmartnodesCore/Coordinator.
 * @dev Features reward assignment during SmartnodesCore state updates, which can be claimed by workers and validators.
 * @dev Provides a locking mechanism for validators on SmartnodesCore, and a yearly reward reduction mechanism.
 */
contract SmartnodesToken is ERC20 {
    /** Errors */
    error SmartnodesToken__InsufficientBalance();
    error SmartnodesToken__InvalidAddress();
    error SmartnodesToken__AlreadyLocked();
    error SmartnodesToken__NotLocked();
    error SmartnodesToken__UnlockPending();
    error SmartnodesToken__TransferFailed();

    struct LockedTokens {
        bool locked;
        uint128 unlockTime;
    }

    /** Constants */
    uint8 private constant VALIDATOR_REWARD_PERCENTAGE = 10;
    uint8 private constant DAO_REWARD_PERCENTAGE = 5;
    uint256 private constant INITIAL_EMISSION_RATE = 5832e18;
    uint256 private constant TAIL_EMISSION = 512e18;
    uint256 private constant REWARD_PERIOD = 365 days; // 1 year in seconds
    uint256 private constant UNLOCK_PERIOD = 14 days;
    uint256 private immutable i_deploymentTimestamp;
    ISmartnodesCore private immutable i_smartnodesCore;

    /** State Variables */
    uint256 public s_lockAmount = 500_000e18;
    uint256 public s_userLockAmount = 500e18;
    uint256 public s_daoTokenFunds;
    uint256 public s_daoEthFunds;
    uint256 public s_totalTokensUnclaimed;
    uint256 public s_totalEthUnclaimed;

    mapping(address => LockedTokens) private s_lockedTokens;
    mapping(address => uint256) private s_unclaimedRewards;
    mapping(address => uint256) private s_unclaimedEthRewards;
    mapping(address => uint256) private s_totalClaimed;
    mapping(address => uint256) private s_escrowedPayments;
    mapping(address => uint256) private s_escrowedEthPayments;

    modifier onlySmartnodesCore() {
        if (msg.sender != address(i_smartnodesCore)) {
            revert SmartnodesToken__InvalidAddress();
        }
        _;
    }

    event PaymentEscrowed(
        address indexed user,
        uint256 payment,
        uint8 networkId
    );
    event EthPaymentEscrowed(
        address indexed user,
        uint256 payment,
        uint8 networkId
    );
    event EscrowReleased(address indexed user, uint256 amount);
    event EthEscrowReleased(address indexed user, uint256 amount);
    event TokensLocked(address indexed validator, uint256 amount);
    event TokensUnlocked(address indexed validator, uint256 amount);
    event UnlockInitiated(address indexed validator, uint256 unlockTime);
    event EthRewardsClaimed(address indexed user, uint256 amount);
    event TokenRewardsClaimed(address indexed user, uint256 amount);

    constructor(
        address[] memory _genesisNodes,
        address _smartnodesCore
    ) ERC20("SmartnodesToken", "SNO") {
        i_smartnodesCore = ISmartnodesCore(_smartnodesCore);
        i_deploymentTimestamp = block.timestamp;

        // Mint initial tokens to genesis nodes
        uint256 gensisNodesLength = _genesisNodes.length;
        for (uint256 i = 0; i < gensisNodesLength; i++) {
            _mint(_genesisNodes[i], s_lockAmount);
        }
    }

    // ============ Locking & Payments ============

    /**
     * @notice Lock tokens for a validator
     * @param _validator The address of the validator locking tokens
     */
    function lockTokens(address _validator) external onlySmartnodesCore {
        if (_validator == address(0)) {
            revert SmartnodesToken__InvalidAddress();
        }
        if (balanceOf(_validator) < s_lockAmount) {
            revert SmartnodesToken__InsufficientBalance();
        }

        LockedTokens storage locked = s_lockedTokens[_validator];
        if (locked.locked) revert SmartnodesToken__AlreadyLocked();
        locked.locked = true;
        _transfer(_validator, address(this), s_lockAmount);
        emit TokensLocked(_validator, s_lockAmount);
    }

    /**
     * @notice Unlock tokens for a validator after the unlock period
     * @dev Can be called once to initiate the unlock process, and once again for claiming tokens after the unlock period
     * @param _validator The address of the validator unlocking tokens
     */
    function unlockTokens(address _validator) external onlySmartnodesCore {
        if (_validator == address(0)) {
            revert SmartnodesToken__InvalidAddress();
        }

        LockedTokens storage locked = s_lockedTokens[_validator];
        if (!locked.locked) {
            // If locked is false, the tokens are either already unlocking or were never locked
            if (locked.unlockTime == 0) {
                // If tokens were never locked, revert
                revert SmartnodesToken__NotLocked();
            }

            // Check if the unlock period has passed
            if (block.timestamp < locked.unlockTime + UNLOCK_PERIOD) {
                revert SmartnodesToken__UnlockPending();
            }

            // Finalize the unlock process
            delete s_lockedTokens[_validator];
            _transfer(address(this), _validator, s_lockAmount);
            emit TokensUnlocked(_validator, s_lockAmount);
        } else {
            // If locked is true, initiate the unlock process
            locked.locked = false;
            locked.unlockTime = uint128(block.timestamp);
            emit UnlockInitiated(_validator, locked.unlockTime);
        }
    }

    /**
     * @notice Escrow payment for a job
     * @param _user The address of the user receiving the payment
     * @param _payment The amount of payment to be escrowed
     * @param _networkId The ID of the network for which the payment is being made
     */
    function escrowPayment(
        address _user,
        uint256 _payment,
        uint8 _networkId
    ) external onlySmartnodesCore {
        if (_user == address(0)) {
            revert SmartnodesToken__InvalidAddress();
        }
        if (_payment == 0 || balanceOf(_user) < _payment) {
            revert SmartnodesToken__InsufficientBalance();
        }

        // Transfer payment to the contract
        _transfer(_user, address(this), _payment);
        s_escrowedPayments[_user] += _payment;
        emit PaymentEscrowed(_user, _payment, _networkId);
    }

    /**
     * @notice Escrow ETH payment for a job
     * @param _user The address of the user making the payment
     * @param _payment The amount of ETH payment to be escrowed
     * @param _networkId The ID of the network for which the payment is being made
     */
    function escrowEthPayment(
        address _user,
        uint256 _payment,
        uint8 _networkId
    ) external payable onlySmartnodesCore {
        if (_user == address(0)) {
            revert SmartnodesToken__InvalidAddress();
        }
        if (_payment == 0 || msg.value < _payment) {
            revert SmartnodesToken__InsufficientBalance();
        }

        s_escrowedEthPayments[_user] += _payment;
        emit EthPaymentEscrowed(_user, _payment, _networkId);
    }

    /**
     * @notice Release escrowed payment to distribute as rewards
     * @param _user The address of the user who made the payment
     * @param _amount The amount of payment to be released
     * @dev Can only be called by SmartnodesCore
     */
    function releaseEscrowedPayment(
        address _user,
        uint256 _amount
    ) external onlySmartnodesCore {
        if (_user == address(0)) {
            revert SmartnodesToken__InvalidAddress();
        }
        if (_amount == 0 || s_escrowedPayments[_user] < _amount) {
            revert SmartnodesToken__InsufficientBalance();
        }

        // Transfer the escrowed payment to the user
        s_escrowedPayments[_user] -= _amount;
        emit EscrowReleased(_user, _amount);
    }

    /**
     * @notice Release escrowed ETH payment for reward distribution
     * @param _user The address of the user whose escrowed ETH payment is being released
     * @param _amount The amount of escrowed ETH payment to be released
     * @dev This releases the escrowed ETH to be available for distribution as rewards
     * @dev The ETH stays in the contract but is no longer considered "escrowed"
     */
    function releaseEscrowedEthPayment(
        address _user,
        uint256 _amount
    ) external onlySmartnodesCore {
        if (_user == address(0)) {
            revert SmartnodesToken__InvalidAddress();
        }
        if (_amount == 0 || s_escrowedEthPayments[_user] < _amount) {
            revert SmartnodesToken__InsufficientBalance();
        }

        // Reduce the escrowed amount (ETH stays in contract for reward distribution)
        s_escrowedEthPayments[_user] -= _amount;
        emit EthEscrowReleased(_user, _amount);
    }

    // ============ Emissions & Halving ============

    /**
     * @notice Distribute rewards to workers and validators
     * @param _validators Array of validator addresses who voted
     * @param _workers Array of worker addresses who performed work
     * @param _capacities Array of capacities for each worker (not used in this implementation)
     * @param _additionalReward Additional reward to be added to the current emission rate
     * @dev Workers receive 90% of the total reward, validators receive 10%
     * @dev Rewards are distributed evenly among validators who voted, and distributed proportionally to workers based on their capacities
     * @dev Workers and validators can claim their rewards later
     * @dev This function is called by SmartnodesCore during state updates to distribute rewards
     */
    function mintRewards(
        address[] calldata _validators,
        address[] calldata _workers,
        uint256[] calldata _capacities,
        uint256 _additionalReward,
        uint256 _additionalEthReward
    ) external onlySmartnodesCore {
        uint256 workersLength = _workers.length;
        uint256 validatorsLength = _validators.length;
        uint256 capacitiesLength = _capacities.length;

        // Get current emission rate and calculate total rewards to mint
        uint256 currentEmission = getEmissionRate();
        uint256 totalTokenReward = currentEmission + _additionalReward;
        uint256 totalEthReward = _additionalEthReward;

        // Calculate DAO reward
        uint256 daoTokenReward = (totalTokenReward * DAO_REWARD_PERCENTAGE) /
            100;
        totalTokenReward -= daoTokenReward;
        uint256 daoEthReward = (totalEthReward * DAO_REWARD_PERCENTAGE) / 100;
        totalEthReward -= daoEthReward;

        // Calculate split of total reward for validators and workers
        uint256 validatorTokenReward;
        uint256 workerTokenReward;
        uint256 validatorEthReward;
        uint256 workerEthReward;
        if (workersLength == 0) {
            validatorTokenReward = totalTokenReward;
            validatorEthReward = totalEthReward;
        } else {
            workerTokenReward =
                (totalTokenReward * (100 - VALIDATOR_REWARD_PERCENTAGE)) /
                100;
            validatorTokenReward = totalTokenReward - workerTokenReward;
            workerEthReward =
                (totalEthReward * (100 - VALIDATOR_REWARD_PERCENTAGE)) /
                100;
            validatorEthReward = totalEthReward - workerEthReward;
        }

        // Update state
        s_daoTokenFunds += daoTokenReward;
        s_daoEthFunds += daoEthReward;
        s_totalTokensUnclaimed += totalTokenReward;
        s_totalEthUnclaimed += totalEthReward;

        // Calculate share of reward for each validator (distributed equally)
        uint256 validatorShare = validatorTokenReward / validatorsLength;
        uint256 validatorEthShare;
        if (totalEthReward > 0) {
            validatorEthShare = validatorEthReward / validatorsLength;
        }

        // Distribute rewards among validators who voted
        for (uint256 i = 0; i < validatorsLength; ) {
            s_unclaimedRewards[_validators[i]] += validatorShare;
            if (validatorEthShare > 0) {
                s_unclaimedEthRewards[_validators[i]] += validatorEthShare;
            }
            unchecked {
                ++i;
            }
        }

        // Distribute rewards among workers proportional to their capacities
        if (workersLength > 0) {
            // Calculate total capacity of all workers
            uint256 totalCapacity;
            for (uint256 i = 0; i < capacitiesLength; ) {
                totalCapacity += _capacities[i];
                unchecked {
                    ++i;
                }
            }

            if (totalCapacity > 0) {
                for (uint256 i = 0; i < workersLength; ) {
                    // Distribute token reward claims
                    uint256 tokenShare = (workerTokenReward * _capacities[i]) /
                        totalCapacity;
                    s_unclaimedRewards[_workers[i]] += tokenShare;

                    // Distribute ETH reward claims if applicable
                    if (workerEthReward > 0) {
                        uint256 ethShare = (workerEthReward * _capacities[i]) /
                            totalCapacity;
                        s_unclaimedEthRewards[_workers[i]] += ethShare;
                    }

                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    /**
     * @notice Claim unclaimed rewards for a worker or validator
     * @dev Workers and validators can call this function to claim their unclaimed rewards
     */
    function claimRewards() external {
        uint256 unclaimed = s_unclaimedRewards[msg.sender];

        if (unclaimed == 0) {
            revert SmartnodesToken__InsufficientBalance();
        }

        // Reset unclaimed rewards for the caller
        s_unclaimedRewards[msg.sender] = 0;
        s_totalTokensUnclaimed -= unclaimed;

        // Update total claimed rewards
        s_totalClaimed[msg.sender] += unclaimed;

        // Mint the claimed rewards to the caller
        _mint(msg.sender, unclaimed);
    }

    /**
     * @return era 0 for the first era, 1 after the first year, 2 after the second, …
     */
    function _currentEra() internal view returns (uint256 era) {
        unchecked {
            era = (block.timestamp - i_deploymentTimestamp) / REWARD_PERIOD;
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

        // Each era is 3/5 of the previous era
        uint256 emission = INITIAL_EMISSION_RATE;
        for (uint256 i = 0; i < era; ) {
            emission = (emission / 5) * 3;
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

    /**
     * @notice Get current emission rate based on era
     */
    function getEmissionRate() public view returns (uint256 emissionRate) {
        uint256 era = _currentEra();
        emissionRate = _emissionForEra(era);
    }

    // =============== DAO Functions ===============
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";

// import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
// import {ERC20Permit} from "@openzeppelin/contracts/token/ER
// import {Govenor} from "@openzeppelin/contracts/governance/Governor.sol";

/**
 * @title Smartnodes Payment and Governance Token
 * @dev Non-upgradeable ERC20 token for job payments and rewards with governance capabilities for SmartnodesCore/Coordinator.
 * @dev Features reward assignment during SmartnodesCore state updates, which can be claimed by workers and validators.
 * @dev Provides a locking mechanism for validators on SmartnodesCore, and a yearly reward reduction mechanism.
 */
contract SmartnodesToken is ERC20, Ownable {
    /** Errors */
    error Token__InsufficientBalance();
    error Token__InvalidAddress();
    error Token__AlreadyLocked();
    error Token__NotLocked();
    error Token__UnlockPending();
    error Token__TransferFailed();
    error Token__CoreNotSet();
    error Token__CoreAlreadySet();

    struct LockedTokens {
        bool locked;
        bool isValidator;
        uint128 unlockTime;
    }

    struct PaymentAmounts {
        uint128 sno;
        uint128 eth;
    }

    /** Constants */
    uint8 private constant VALIDATOR_REWARD_PERCENTAGE = 10;
    uint8 private constant DAO_REWARD_PERCENTAGE = 5;
    uint256 private constant INITIAL_EMISSION_RATE = 5832e18;
    uint256 private constant TAIL_EMISSION = 512e18;
    uint256 private constant REWARD_PERIOD = 365 days; // 1 year in seconds
    uint256 private constant UNLOCK_PERIOD = 14 days;
    uint256 private immutable i_deploymentTimestamp;

    /** State Variables */
    ISmartnodesCore public s_smartnodesCore; // Mutable reference instead of immutable
    bool public s_coreSet; // Flag to ensure core can only be set once

    uint256 public s_validatorLockAmount = 500_000e18;
    uint256 public s_userLockAmount = 500e18;

    PaymentAmounts public s_daoFunds;
    PaymentAmounts public s_totalUnclaimed;

    mapping(address => LockedTokens) private s_lockedTokens;
    mapping(address => PaymentAmounts) private s_unclaimedRewards;
    mapping(address => PaymentAmounts) private s_totalClaimed;
    mapping(address => PaymentAmounts) private s_escrowedPayments;

    modifier onlySmartnodesCore() {
        if (address(s_smartnodesCore) == address(0)) {
            revert Token__CoreNotSet();
        }
        if (msg.sender != address(s_smartnodesCore)) {
            revert Token__InvalidAddress();
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
    event TokensLocked(address indexed user, bool isValidator, uint256 amount);
    event TokensUnlocked(
        address indexed user,
        bool isValidator,
        uint256 amount
    );
    event UnlockInitiated(address indexed user, uint256 unlockTime);
    event EthRewardsClaimed(address indexed user, uint256 amount);
    event TokenRewardsClaimed(address indexed user, uint256 amount);
    event CoreContractSet(address indexed coreContract);

    constructor(
        address[] memory _genesisNodes
    ) ERC20("SmartnodesToken", "SNO") Ownable(msg.sender) {
        i_deploymentTimestamp = block.timestamp;
        s_coreSet = false;

        // Mint initial tokens to genesis nodes
        uint256 gensisNodesLength = _genesisNodes.length;
        for (uint256 i = 0; i < gensisNodesLength; i++) {
            _mint(_genesisNodes[i], s_validatorLockAmount * 2);
        }
    }

    /**
     * @dev Sets the SmartnodesCore contract address. Can only be called once by owner.
     * @param _smartnodesCore Address of the deployed SmartnodesCore contract
     */
    function setSmartnodesCore(address _smartnodesCore) external onlyOwner {
        if (s_coreSet) {
            revert Token__CoreAlreadySet();
        }
        if (_smartnodesCore == address(0)) {
            revert Token__InvalidAddress();
        }

        s_smartnodesCore = ISmartnodesCore(_smartnodesCore);
        s_coreSet = true;

        emit CoreContractSet(_smartnodesCore);
    }

    // ============ Locking & Payments ============

    /**
     * @notice Lock tokens for a validator or user
     * @param _user The address of the validator locking tokens
     */
    function lockTokens(
        address _user,
        bool _isValidator
    ) external onlySmartnodesCore {
        if (_user == address(0)) {
            revert Token__InvalidAddress();
        }

        uint256 lockAmount;

        if (_isValidator) {
            lockAmount = s_validatorLockAmount;
        } else {
            lockAmount = s_userLockAmount;
        }

        if (balanceOf(_user) < lockAmount) {
            revert Token__InsufficientBalance();
        }

        LockedTokens storage locked = s_lockedTokens[_user];
        if (locked.locked) revert Token__AlreadyLocked();

        locked.locked = true;
        locked.isValidator = _isValidator;

        _transfer(_user, address(this), lockAmount);
        emit TokensLocked(_user, _isValidator, lockAmount);
    }

    /**
     * @notice Unlock tokens for a user after the unlock period
     * @dev Can be called once to initiate the unlock process, and once again for claiming tokens after the unlock period
     * @param _user The address of the user unlocking tokens
     */
    function unlockTokens(address _user) external onlySmartnodesCore {
        if (_user == address(0)) {
            revert Token__InvalidAddress();
        }

        LockedTokens storage locked = s_lockedTokens[_user];
        if (!locked.locked) {
            // If locked is false, the tokens are either already unlocking or were never locked
            if (locked.unlockTime == 0) {
                // If tokens were never locked, revert
                revert Token__NotLocked();
            }

            // Check if the unlock period has passed
            if (block.timestamp < locked.unlockTime + UNLOCK_PERIOD) {
                revert Token__UnlockPending();
            }

            // Finalize the unlock process
            uint256 lockAmount;
            if (locked.isValidator) {
                lockAmount = s_validatorLockAmount;
            } else {
                lockAmount = s_userLockAmount;
            }

            delete s_lockedTokens[_user];
            _transfer(address(this), _user, lockAmount);
            emit TokensUnlocked(_user, locked.isValidator, lockAmount);
        } else {
            // If locked is true, initiate the unlock process
            locked.locked = false;
            locked.unlockTime = uint128(block.timestamp);
            emit UnlockInitiated(_user, locked.unlockTime);
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
            revert Token__InvalidAddress();
        }
        if (_payment == 0 || balanceOf(_user) < _payment) {
            revert Token__InsufficientBalance();
        }

        // Transfer payment to the contract
        _transfer(_user, address(this), _payment);
        s_escrowedPayments[_user].sno += uint128(_payment);
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
            revert Token__InvalidAddress();
        }
        if (_payment == 0 || msg.value < _payment) {
            revert Token__InsufficientBalance();
        }

        s_escrowedPayments[_user].eth += uint128(_payment);
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
            revert Token__InvalidAddress();
        }
        if (_amount == 0 || s_escrowedPayments[_user].sno < _amount) {
            revert Token__InsufficientBalance();
        }

        // Transfer the escrowed payment to the user
        s_escrowedPayments[_user].sno -= uint128(_amount);
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
            revert Token__InvalidAddress();
        }
        if (_amount == 0 || s_escrowedPayments[_user].eth < _amount) {
            revert Token__InsufficientBalance();
        }

        // Reduce the escrowed amount (ETH stays in contract for reward distribution)
        s_escrowedPayments[_user].eth -= uint128(_amount);
        emit EthEscrowReleased(_user, _amount);
    }

    // ============ Emissions & Halving ============

    /**
     * @notice Distribute rewards to workers and validators
     * @param _validators Array of validator addresses who voted
     * @param _workers Array of worker addresses who performed work
     * @param _capacities Array of capacities for each worker (not used in this implementation)
     * @param _payments Additional payments to be added to the current emission rate
     * @dev Workers receive 90% of the total reward, validators receive 10%
     * @dev Rewards are distributed evenly among validators who voted, and distributed proportionally to workers based on their capacities
     * @dev Workers and validators can claim their rewards later
     * @dev This function is called by SmartnodesCore during state updates to distribute rewards
     */
    function mintRewards(
        address[] calldata _validators,
        address[] calldata _workers,
        uint256[] calldata _capacities,
        PaymentAmounts calldata _payments
    ) external onlySmartnodesCore {
        // Total rewards to be distributed
        PaymentAmounts memory totalReward = PaymentAmounts({
            sno: uint128(getEmissionRate()) + _payments.sno,
            eth: _payments.eth
        });

        // DAO cut
        PaymentAmounts memory daoReward = PaymentAmounts({
            sno: uint128(
                (uint256(totalReward.sno) * DAO_REWARD_PERCENTAGE) / 100
            ),
            eth: uint128(
                (uint256(totalReward.eth) * DAO_REWARD_PERCENTAGE) / 100
            )
        });

        // Update reward storage info
        totalReward.sno -= daoReward.sno;
        totalReward.eth -= daoReward.eth;

        s_daoFunds.sno += daoReward.sno;
        s_daoFunds.eth += daoReward.eth;
        s_totalUnclaimed.sno += totalReward.sno;
        s_totalUnclaimed.eth += totalReward.eth;

        // Split validator/worker share
        PaymentAmounts memory validatorReward = _splitRewardForValidators(
            totalReward
        );
        PaymentAmounts memory workerReward = PaymentAmounts({
            sno: totalReward.sno - validatorReward.sno,
            eth: totalReward.eth - validatorReward.eth
        });

        _distributeToValidators(_validators, validatorReward);
        _distributeToWorkers(_workers, _capacities, workerReward);
    }

    function _splitRewardForValidators(
        PaymentAmounts memory totalReward
    ) internal pure returns (PaymentAmounts memory validatorReward) {
        validatorReward = PaymentAmounts({
            sno: uint128(
                (uint256(totalReward.sno) * VALIDATOR_REWARD_PERCENTAGE) / 100
            ),
            eth: uint128(
                (uint256(totalReward.eth) * VALIDATOR_REWARD_PERCENTAGE) / 100
            )
        });
    }

    function _distributeToValidators(
        address[] calldata validators,
        PaymentAmounts memory totalReward
    ) internal {
        uint256 len = validators.length;
        if (len == 0) return;

        PaymentAmounts memory sharePerValidator = PaymentAmounts({
            sno: uint128(uint256(totalReward.sno) / len),
            eth: uint128(uint256(totalReward.eth) / len)
        });

        for (uint256 i = 0; i < len; ) {
            address v = validators[i];
            s_unclaimedRewards[v].sno += sharePerValidator.sno;
            s_unclaimedRewards[v].eth += sharePerValidator.eth;
            unchecked {
                ++i;
            }
        }
    }

    function _distributeToWorkers(
        address[] calldata workers,
        uint256[] calldata capacities,
        PaymentAmounts memory totalReward
    ) internal {
        uint256 len = workers.length;
        if (len == 0) return;

        uint256 totalCapacity;
        for (uint256 i = 0; i < capacities.length; ) {
            totalCapacity += capacities[i];
            unchecked {
                ++i;
            }
        }
        if (totalCapacity == 0) return;

        for (uint256 i = 0; i < len; ) {
            address w = workers[i];
            uint256 cap = capacities[i];

            PaymentAmounts memory workerShare = PaymentAmounts({
                sno: uint128((uint256(totalReward.sno) * cap) / totalCapacity),
                eth: uint128((uint256(totalReward.eth) * cap) / totalCapacity)
            });

            s_unclaimedRewards[w].sno += workerShare.sno;
            s_unclaimedRewards[w].eth += workerShare.eth;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Claim unclaimed SNO token rewards for a worker or validator
     * @dev Workers and validators can call this function to claim their unclaimed SNO token rewards
     */
    function claimTokenRewards() external {
        uint256 unclaimed = s_unclaimedRewards[msg.sender].sno;

        if (unclaimed == 0) {
            revert Token__InsufficientBalance();
        }

        // Reset unclaimed token rewards for the caller
        s_unclaimedRewards[msg.sender].sno = 0;
        s_totalUnclaimed.sno -= uint128(unclaimed);

        // Update total claimed rewards
        s_totalClaimed[msg.sender].sno += uint128(unclaimed);

        // Mint the claimed rewards to the caller
        _mint(msg.sender, unclaimed);
        emit TokenRewardsClaimed(msg.sender, unclaimed);
    }

    /**
     * @notice Claim unclaimed ETH rewards for a worker or validator
     * @dev Workers and validators can call this function to claim their unclaimed ETH rewards
     */
    function claimEthRewards() external {
        uint256 unclaimed = s_unclaimedRewards[msg.sender].eth;

        if (unclaimed == 0) {
            revert Token__InsufficientBalance();
        }

        // Reset unclaimed ETH rewards for the caller
        s_unclaimedRewards[msg.sender].eth = 0;
        s_totalUnclaimed.eth -= uint128(unclaimed);

        // Update total claimed rewards
        s_totalClaimed[msg.sender].eth += uint128(unclaimed);

        // Transfer ETH to the caller
        (bool success, ) = payable(msg.sender).call{value: unclaimed}("");
        if (!success) {
            revert Token__TransferFailed();
        }
        emit EthRewardsClaimed(msg.sender, unclaimed);
    }

    /**
     * @notice Claim both SNO token and ETH rewards in a single transaction
     * @dev More gas efficient than calling both claim functions separately
     */
    function claimAllRewards() external {
        PaymentAmounts memory unclaimed = s_unclaimedRewards[msg.sender];

        if (unclaimed.sno == 0 && unclaimed.eth == 0) {
            revert Token__InsufficientBalance();
        }

        // Reset all unclaimed rewards for the caller
        delete s_unclaimedRewards[msg.sender];
        s_totalUnclaimed.sno -= unclaimed.sno;
        s_totalUnclaimed.eth -= unclaimed.eth;

        // Update total claimed rewards
        s_totalClaimed[msg.sender].sno += unclaimed.sno;
        s_totalClaimed[msg.sender].eth += unclaimed.eth;

        // Mint SNO tokens if any
        if (unclaimed.sno > 0) {
            _mint(msg.sender, unclaimed.sno);
            emit TokenRewardsClaimed(msg.sender, unclaimed.sno);
        }

        // Transfer ETH if any
        if (unclaimed.eth > 0) {
            (bool success, ) = payable(msg.sender).call{value: unclaimed.eth}(
                ""
            );
            if (!success) {
                revert Token__TransferFailed();
            }
            emit EthRewardsClaimed(msg.sender, unclaimed.eth);
        }
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

    // =============== View Functions ===============

    /**
     * @dev Get the current SmartnodesCore contract address
     */
    function getSmartnodesCore() external view returns (address) {
        return address(s_smartnodesCore);
    }

    /**
     * @dev Get unclaimed rewards for a specific address
     */
    function getUnclaimedRewards(
        address _user
    ) external view returns (PaymentAmounts memory) {
        return s_unclaimedRewards[_user];
    }

    /**
     * @dev Get total claimed rewards for a specific address
     */
    function getTotalClaimed(
        address _user
    ) external view returns (PaymentAmounts memory) {
        return s_totalClaimed[_user];
    }

    function getTotalUnclaimed() external view returns (uint128, uint128) {
        PaymentAmounts storage totalUnclaimed = s_totalUnclaimed;
        return (totalUnclaimed.sno, totalUnclaimed.eth);
    }

    /**
     * @dev Get escrowed payments for a specific address
     */
    function getEscrowedPayments(
        address _user
    ) external view returns (PaymentAmounts memory) {
        return s_escrowedPayments[_user];
    }
}

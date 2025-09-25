// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";
import {ISmartnodesCoordinator} from "./interfaces/ISmartnodesCoordinator.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Payment and Governance Token for the Smartnodes Network
 * @dev Non-upgradeable ERC20 token for job payments, node rewards, and node collateral.
 * @dev Rewards are distributed perioidcally by the SmartnodesCore and SmartnodesCoordinator.
 * @dev Reward distribution undergoes yearly 40% reductions until a tail emission is reached.
 * @dev Uses simple DAO-based access control system to control staking requirements and upgrades
 * @dev to SmartnodesCore and SmartnodesCoordinator.
 */
contract SmartnodesERC20 is ERC20, ERC20Permit, ERC20Votes, ReentrancyGuard {
    /** Errors */
    error Token__InsufficientBalance();
    error Token__InvalidAddress();
    error Token__AlreadyLocked();
    error Token__NotLocked();
    error Token__UnlockPending();
    error Token__TransferFailed();
    error Token__CoreNotSet();
    error Token__DAONotSet();
    error Token__CoreAlreadySet();
    error Token__InvalidMerkleRoot();
    error Token__InvalidMerkleProof();
    error Token__RewardsAlreadyClaimed();
    error Token__InvalidArrayLength();
    error Token__ETHTransferFailed();
    error Token__OnlyDAO();
    error Token__DAOAlreadySet();
    error Token__DistributionTooEarly();
    error Token__InvalidInterval();
    error Token__DistributionTooOld();
    error Token__NotValidator();

    // Token lock struct for both validators and users
    struct LockedTokens {
        bool locked;
        bool isValidator;
        uint128 unlockTime;
        uint256 lockedAmount;
    }

    // Job payments and rewards can be SNO or ETH
    struct PaymentAmounts {
        uint128 sno;
        uint128 eth;
    }

    struct EthBreakdown {
        uint256 totalContractEth;
        uint256 unclaimedEth;
        uint256 escrowedEth;
        uint256 availableEth;
    }

    struct MerkleDistribution {
        bytes32 merkleRoot;
        PaymentAmounts workerReward;
        uint256 totalCapacity;
        uint256 timestamp;
        uint256 nonce;
    }

    /** Constants */
    uint8 private constant VALIDATOR_REWARD_PERCENTAGE = 10;
    uint8 private constant DAO_REWARD_PERCENTAGE = 5;
    uint256 private constant BASE_EMISSION_RATE = 5625e18; // Base 1 hour emission rate
    uint256 private constant TAIL_EMISSION = 420e18; // Base 1 hour tail emission
    uint256 private constant REWARD_PERIOD = 365 days;
    uint256 private constant UNLOCK_PERIOD = 30 days;
    uint256 private constant INITIAL_INTERVAL = 8; // Start with 128 hour interval for emission calculation
    uint256 private constant MAX_INTERVAL = 256; // Minimum and maximum distribution intervals (# hours)
    uint256 private constant MIN_INTERVAL = 1;
    uint256 private constant MAX_BATCH_SIZE = 100; // Batch reward claim limit for a single call
    uint256 private constant MAX_DISTRIBUTIONS = 500;
    uint256 public immutable i_deploymentTimestamp;

    /** State Variables */
    ISmartnodesCore public s_smartnodesCore;
    ISmartnodesCoordinator public s_smartnodesCoordinator;
    bool public s_coreSet;
    address public s_dao;
    bool public s_daoSet;

    // Initial lock requirements
    uint256 public s_validatorLockAmount;
    uint256 public s_userLockAmount;

    // Payment and rewards tracking (SNO + ETH)
    PaymentAmounts public s_totalUnclaimed;
    PaymentAmounts public s_totalEscrowed;
    uint256 public s_totalLocked; // SNO
    uint256 public s_totalETHDeposited;
    uint256 public s_totalETHWithdrawn;

    uint256 public s_currentDistributionId;
    uint256 public s_distributionInterval;
    uint256 public s_lastDistributionTime;

    mapping(uint256 => MerkleDistribution) public s_distributions;
    mapping(uint256 => mapping(address => bool)) public s_claimed;
    mapping(address => LockedTokens) public s_lockedTokens;
    mapping(address => PaymentAmounts) public s_escrowedPayments;

    /** Modifiers */
    modifier onlySmartnodesCore() {
        if (address(s_smartnodesCore) == address(0)) {
            revert Token__CoreNotSet();
        }
        if (msg.sender != address(s_smartnodesCore)) {
            revert Token__InvalidAddress();
        }
        _;
    }

    modifier onlyDAO() {
        address dao = s_dao;
        if (dao != address(0)) {
            if (msg.sender != dao) {
                revert Token__OnlyDAO();
            }
        }
        _;
    }

    /** Events */
    event PaymentEscrowed(address indexed user, uint256 payment);
    event EthPaymentEscrowed(address indexed user, uint256 payment);
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
    event TokenRewardsClaimed(
        uint256 indexed distributionId,
        address indexed user,
        uint256 amount
    );
    event ClaimFailed(
        uint256 indexed distributionId,
        address indexed user,
        string reason
    );
    event SmartnodesSet(
        address indexed coreContract,
        address indexed coordinatorContract
    );
    event DAOSet(address indexed dao);
    event ValidatorLockAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event UserLockAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MerkleDistributionCreated(
        uint256 indexed distributionId,
        bytes32 merkleRoot,
        uint256 totalSnoRewards,
        uint256 totalEthRewards,
        uint256 timestamp
    );
    event ValidatorRewardsDistributed(
        uint256 indexed distributionId,
        address[] validators,
        uint256 totalSno,
        uint256 totalEth
    );
    event DAORewardsDistributed(
        uint256 indexed distributionId,
        uint256 snoAmount,
        uint256 ethAmount
    );
    event ETHDeposited(address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event DistributionIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event DistributionExpired(uint256 distributionId);
    event ValidatorSlashed(
        address indexed validator,
        uint256 slashedAmount,
        uint256 remainingAmount
    );
    event SlashedTokensBurned(uint256 amount);

    constructor(
        address[] memory _genesisNodes
    ) ERC20("Smartnodes", "SNO") ERC20Permit("Smartnodes") {
        i_deploymentTimestamp = block.timestamp;
        s_coreSet = false;
        s_daoSet = false;

        // Set initial distribution interval based on emission multiplier
        s_distributionInterval = INITIAL_INTERVAL;
        s_validatorLockAmount = 1_000_000e18;
        s_userLockAmount = 100e18;

        // Mint initial tokens to genesis nodes
        uint256 gensisNodesLength = _genesisNodes.length;
        for (uint256 i = 0; i < gensisNodesLength; i++) {
            _mint(_genesisNodes[i], (s_validatorLockAmount * 3));
        }
    }

    receive() external payable {
        s_totalETHDeposited += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }

    // ============ DAO Setup ============
    /**
     * @dev Sets the DAO contract address. Can only be called once by deployer before DAO is set.
     * @param _dao Address of the deployed DAO contract
     */
    function setDAO(address _dao) external {
        if (s_daoSet) {
            revert Token__DAOAlreadySet();
        }
        if (_dao == address(0)) {
            revert Token__InvalidAddress();
        }

        s_dao = _dao;
        s_daoSet = true;

        emit DAOSet(_dao);
    }

    // ============ Emissions & Halving ============

    /**
     * @notice Distribute validator rewards
     * @param _approvedValidators List of validators that voted
     * @param _validatorReward Total reward amounts for validators
     * @param _distributionId Current distribution ID for events
     * @param _dustValidator Validator that gets the scraps (proposal creator)
     */
    function _distributeValidatorRewards(
        address[] memory _approvedValidators,
        PaymentAmounts memory _validatorReward,
        uint256 _distributionId,
        address _dustValidator
    ) internal {
        uint8 _nValidators = uint8(_approvedValidators.length);

        // Remaining pool to be split equally among validators
        uint256 snoPool = uint256(_validatorReward.sno);
        uint256 ethPool = uint256(_validatorReward.eth);

        uint256 snoPerValidator = snoPool / _nValidators;
        uint256 ethPerValidator = ethPool / _nValidators;

        // Handle dust/remainder
        uint256 snoRemainder = snoPool - (snoPerValidator * _nValidators);
        uint256 ethRemainder = ethPool - (ethPerValidator * _nValidators);

        // Distribute to validators
        for (uint256 i = 0; i < _nValidators; i++) {
            address validator = _approvedValidators[i];
            if (validator == address(0)) revert Token__InvalidAddress();

            uint256 snoShare = snoPerValidator;
            uint256 ethShare = ethPerValidator;

            // Give dust to first validator to avoid lost remainder
            if (_dustValidator == validator) {
                snoShare += snoRemainder;
                ethShare += ethRemainder;
            }

            _payAccount(validator, snoShare, ethShare);
        }

        emit ValidatorRewardsDistributed(
            _distributionId,
            _approvedValidators,
            _validatorReward.sno,
            _validatorReward.eth
        );
    }

    /**
     * @notice Helper function to pay a validator both SNO tokens and ETH
     * @param validator Address of the validator to pay
     * @param snoAmount Amount of SNO tokens to mint/send
     * @param ethAmount Amount of ETH to transfer
     */
    function _payAccount(
        address validator,
        uint256 snoAmount,
        uint256 ethAmount
    ) internal {
        // Check ETH balance before transfer
        if (ethAmount > 0 && address(this).balance < ethAmount) {
            revert Token__InsufficientBalance();
        }

        if (snoAmount > 0) {
            _mint(validator, snoAmount);
        }

        if (ethAmount > 0) {
            s_totalETHWithdrawn += ethAmount;
            (bool sent, ) = validator.call{value: ethAmount}("");
            if (!sent) revert Token__ETHTransferFailed();
        }
    }

    /**
     * @notice Distribute rewards to workers and validators
     * @param _merkleRoot Root of state update and payments data
     * @param _totalCapacity Total capacity of contributed workers
     * @param _payments Additional payments to be added to the current emission rate
     * @param _approvedValidators List of validators that voted
     * @param _dustValidator Address of validator to receive dust rewards (usually the proposal executor)
     * @dev Workers receive 85% of the total reward, validators receive 10%, dao receives 5%
     * @dev Rewards are distributed proportionally to workers based on their capacities.
     * @dev This function is called periodically by SmartnodesCore during state updates to distribute rewards.
     */
    function createMerkleDistribution(
        bytes32 _merkleRoot,
        uint256 _totalCapacity,
        address[] memory _approvedValidators,
        PaymentAmounts calldata _payments,
        address _dustValidator
    ) external onlySmartnodesCore nonReentrant {
        uint8 _nValidators = uint8(_approvedValidators.length);
        if (_nValidators == 0) revert Token__InvalidArrayLength();

        if (s_lastDistributionTime != 0) {
            if (
                block.timestamp <
                s_lastDistributionTime + s_distributionInterval
            ) {
                revert Token__DistributionTooEarly();
            }
        }
        s_lastDistributionTime = block.timestamp;

        // Total rewards to be distributed
        PaymentAmounts memory totalReward = PaymentAmounts({
            sno: uint128(getEmissionRate() + _payments.sno),
            eth: _payments.eth
        });

        // Check ETH balance before proceeding
        if (totalReward.eth > 0 && address(this).balance < totalReward.eth) {
            revert Token__InsufficientBalance();
        }

        uint256 distributionId = ++s_currentDistributionId;

        // Calculate reward distributions
        PaymentAmounts memory daoReward = PaymentAmounts({
            sno: uint128(
                (uint256(totalReward.sno) * DAO_REWARD_PERCENTAGE) / 100
            ),
            eth: uint128(
                (uint256(totalReward.eth) * DAO_REWARD_PERCENTAGE) / 100
            )
        });

        // Split validator/worker share from the remaining pool
        PaymentAmounts memory validatorReward = PaymentAmounts({
            sno: uint128(
                (uint256(totalReward.sno) * VALIDATOR_REWARD_PERCENTAGE) / 100
            ),
            eth: uint128(
                (uint256(totalReward.eth) * VALIDATOR_REWARD_PERCENTAGE) / 100
            )
        });

        if (_totalCapacity != 0) {
            PaymentAmounts memory workerReward = PaymentAmounts({
                sno: totalReward.sno - validatorReward.sno - daoReward.sno,
                eth: totalReward.eth - validatorReward.eth - daoReward.eth
            });

            // Store merkle distribution (only worker rewards are stored for claiming)
            s_distributions[distributionId] = MerkleDistribution({
                merkleRoot: _merkleRoot,
                workerReward: workerReward,
                totalCapacity: _totalCapacity,
                timestamp: block.timestamp,
                nonce: distributionId
            });

            // Update total unclaimed (only worker rewards)
            s_totalUnclaimed.sno += workerReward.sno;
            s_totalUnclaimed.eth += workerReward.eth;

            emit MerkleDistributionCreated(
                distributionId,
                _merkleRoot,
                totalReward.sno,
                totalReward.eth,
                block.timestamp
            );
        }

        // Clean up oldest distribution if we exceed MAX_DISTRIBUTIONS
        if (distributionId > MAX_DISTRIBUTIONS) {
            _cleanupOldestDistribution();
        }

        // Distribute DAO rewards
        _payAccount(s_dao, daoReward.sno, daoReward.eth);
        emit DAORewardsDistributed(
            distributionId,
            daoReward.sno,
            daoReward.eth
        );

        // Distribute validator rewards
        _distributeValidatorRewards(
            _approvedValidators,
            validatorReward,
            distributionId,
            _dustValidator
        );
    }

    /**
     * @notice Internal function to clean up the oldest distribution when we exceed MAX_DISTRIBUTIONS
     * @dev This function is called automatically when creating a new distribution
     */
    function _cleanupOldestDistribution() internal {
        uint256 currentId = s_currentDistributionId;

        if (currentId > MAX_DISTRIBUTIONS) {
            uint256 oldestId = currentId - MAX_DISTRIBUTIONS;

            delete s_distributions[oldestId];
            emit DistributionExpired(oldestId);
        }
    }

    /**
     * @notice Claim rewards from a single Merkle distribution
     * @param _distributionId The ID of the distribution to claim from
     * @param _capacity Worker capacity associated with rewards claim
     * @param _merkleProof Merkle proof validating the claim
     * @dev Users can claim their rewards by providing a valid Merkle proof
     */
    function claimMerkleRewards(
        uint256 _distributionId,
        uint256 _capacity,
        bytes32[] calldata _merkleProof
    ) external nonReentrant {
        // Create single-element arrays and delegate to batch function
        uint256[] memory distributionIds = new uint256[](1);
        uint256[] memory capacities = new uint256[](1);
        bytes32[][] memory merkleProofs = new bytes32[][](1);

        distributionIds[0] = _distributionId;
        capacities[0] = _capacity;
        merkleProofs[0] = _merkleProof;

        // Remove nonReentrant from this function since batch function has it
        _batchClaimMerkleRewards(distributionIds, capacities, merkleProofs);
    }

    /**
     * @notice Batch claim rewards from multiple Merkle distributions
     * @param _distributionIds Array of distribution IDs to claim from
     * @param _capacities Array of worker capacities associated with each claim
     * @param _merkleProofs Array of merkle proofs validating each claim
     * @dev All arrays must be the same length. Claims are processed in order.
     */
    function batchClaimMerkleRewards(
        uint256[] calldata _distributionIds,
        uint256[] calldata _capacities,
        bytes32[][] calldata _merkleProofs
    ) external nonReentrant {
        // Convert calldata to memory and delegate to internal function
        uint256 length = _distributionIds.length;
        uint256[] memory distributionIds = new uint256[](length);
        uint256[] memory capacities = new uint256[](length);
        bytes32[][] memory merkleProofs = new bytes32[][](length);

        for (uint256 i; i < length; ) {
            distributionIds[i] = _distributionIds[i];
            capacities[i] = _capacities[i];
            merkleProofs[i] = _merkleProofs[i];
            unchecked {
                ++i;
            }
        }

        _batchClaimMerkleRewards(distributionIds, capacities, merkleProofs);
    }

    function _batchClaimMerkleRewards(
        uint256[] memory _distributionIds,
        uint256[] memory _capacities,
        bytes32[][] memory _merkleProofs
    ) internal {
        uint256 length = _distributionIds.length;
        if (
            length != _capacities.length ||
            length != _merkleProofs.length ||
            length > MAX_BATCH_SIZE
        ) {
            revert Token__InvalidArrayLength();
        }

        uint256 currentDistribution = s_currentDistributionId;

        // Accumulate all rewards before any storage writes
        uint256 totalSnoReward;
        uint256 totalEthReward;

        // Pre-validate all claims and calculate totals
        for (uint256 i; i < length; ) {
            uint256 distributionId = _distributionIds[i];
            MerkleDistribution storage distribution = s_distributions[
                distributionId
            ];

            // Pack validation checks
            if (
                currentDistribution > MAX_DISTRIBUTIONS ||
                s_claimed[distributionId][msg.sender]
            ) {
                // Use specific reverts based on which condition failed
                if (s_claimed[distributionId][msg.sender])
                    revert Token__RewardsAlreadyClaimed();
                if (distributionId < currentDistribution - MAX_DISTRIBUTIONS)
                    revert Token__DistributionTooOld();
            }

            // Verify merkle proof
            bytes32 leaf = keccak256(
                abi.encode(msg.sender, _capacities[i], distribution.nonce)
            );
            if (
                !MerkleProof.verify(
                    _merkleProofs[i],
                    distribution.merkleRoot,
                    leaf
                )
            ) {
                revert Token__InvalidMerkleProof();
            }

            // Calculate rewards and accumulate
            uint256 capacity = _capacities[i];
            uint256 totalCapacity = distribution.totalCapacity;

            // Use unchecked math where safe to save gas
            unchecked {
                totalSnoReward +=
                    (distribution.workerReward.sno * capacity) /
                    totalCapacity;
                totalEthReward +=
                    (distribution.workerReward.eth * capacity) /
                    totalCapacity;
                ++i;
            }
        }

        // Batch update all claimed statuses in single loop
        for (uint256 i; i < length; ) {
            s_claimed[_distributionIds[i]][msg.sender] = true;
            unchecked {
                ++i;
            }
        }

        // Single storage update for total unclaimed
        if (totalSnoReward > 0) {
            s_totalUnclaimed.sno -= uint128(totalSnoReward);
            _mint(msg.sender, totalSnoReward);

            // Emit single event for all SNO rewards
            emit TokenRewardsClaimed(0, msg.sender, totalSnoReward); // Use 0 for batch claims
        }

        if (totalEthReward > 0) {
            if (address(this).balance < totalEthReward)
                revert Token__InsufficientBalance();

            s_totalUnclaimed.eth -= uint128(totalEthReward);
            s_totalETHWithdrawn += totalEthReward;

            // Assembly for gas-efficient ETH transfer
            assembly {
                let success := call(gas(), caller(), totalEthReward, 0, 0, 0, 0)
                if iszero(success) {
                    mstore(0x00, 0x90b8ec18) // Token__ETHTransferFailed()
                    revert(0x1c, 0x04)
                }
            }
            emit EthRewardsClaimed(msg.sender, totalEthReward);
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
        if (era == 0) return BASE_EMISSION_RATE;

        // initial * (0.6)^era
        uint256 emission = BASE_EMISSION_RATE;
        for (uint256 i = 0; i < era; i++) {
            emission = (emission * 300) / 500;
            if (emission <= TAIL_EMISSION) return TAIL_EMISSION;
        }

        return emission;
    }

    /**
     * @notice Get the current emission rate
     * @return Current emission rate for this era
     */
    function getEmissionRate() public view returns (uint256) {
        uint256 era = _currentEra();
        uint256 baseEmission = _emissionForEra(era);
        return (baseEmission * s_distributionInterval);
    }

    /**
     * @notice Get current era number
     * @return Current era (0-based)
     */
    function getCurrentEra() external view returns (uint256) {
        return _currentEra();
    }

    // ============ DAO-Controlled Functions ============

    /**
     * @dev Sets the Smartnodes contract addresses. Can only be called by DAO.
     * @param _smartnodesCore Address of the deployed SmartnodesCore contract
     * @param _smartnodesCoordinator Address of the deployed SmartnodesCoordinator contract
     */
    function setSmartnodes(
        address _smartnodesCore,
        address _smartnodesCoordinator
    ) external onlyDAO {
        if (s_coreSet) {
            revert Token__CoreAlreadySet();
        }
        if (_smartnodesCore == address(0)) {
            revert Token__InvalidAddress();
        }

        s_smartnodesCore = ISmartnodesCore(_smartnodesCore);
        s_smartnodesCoordinator = ISmartnodesCoordinator(
            _smartnodesCoordinator
        );
        s_coreSet = true;

        emit SmartnodesSet(_smartnodesCore, _smartnodesCoordinator);
    }

    /**
     * @dev Sets validator lock amount. Can only be called by DAO.
     * @param _newAmount New validator lock amount
     */
    function setValidatorLockAmount(uint256 _newAmount) external onlyDAO {
        uint256 oldAmount = s_validatorLockAmount;
        s_validatorLockAmount = _newAmount;
        emit ValidatorLockAmountUpdated(oldAmount, _newAmount);
    }

    /**
     * @dev Sets user lock amount. Can only be called by DAO.
     * @param _newAmount New user lock amount
     */
    function setUserLockAmount(uint256 _newAmount) external onlyDAO {
        uint256 oldAmount = s_userLockAmount;
        s_userLockAmount = _newAmount;
        emit UserLockAmountUpdated(oldAmount, _newAmount);
    }

    /**
     * @notice Convenience function to halve the distribution interval
     */
    function halveDistributionInterval() external onlyDAO nonReentrant {
        uint256 oldInterval = s_distributionInterval;
        if (oldInterval <= MIN_INTERVAL) {
            revert Token__InvalidInterval();
        }
        s_distributionInterval = oldInterval / 2;

        s_smartnodesCoordinator.updateTiming(s_distributionInterval);
        emit DistributionIntervalUpdated(oldInterval, s_distributionInterval);
    }

    /**
     * @notice Convenience function to double the distribution interval
     */
    function doubleDistributionInterval() external onlyDAO nonReentrant {
        uint256 oldInterval = s_distributionInterval;
        if (oldInterval >= MAX_INTERVAL) {
            revert Token__InvalidInterval();
        }
        s_distributionInterval = oldInterval * 2;
        s_smartnodesCoordinator.updateTiming(s_distributionInterval);
        emit DistributionIntervalUpdated(oldInterval, s_distributionInterval);
    }

    /**
     * @notice Slash a validator's locked tokens and immediately unlock them
     * @param _validator The address of the validator to slash
     * @param _slashAmount The amount of tokens to slash (burn)
     * @dev Can only be called by DAO. Slashed tokens are burned and remaining tokens are returned to validator.
     * @dev This function combines slashing with timed unlock to prevent further misbehavior.
     */
    function slashAndUnlockValidator(
        address _validator,
        uint256 _slashAmount
    ) external onlyDAO nonReentrant {
        if (_validator == address(0)) {
            revert Token__InvalidAddress();
        }

        LockedTokens storage locked = s_lockedTokens[_validator];

        if (!locked.locked || !locked.isValidator) {
            revert Token__NotValidator();
        }

        uint256 lockedAmount = locked.lockedAmount;
        uint256 remainingAmount = lockedAmount - _slashAmount;

        // Update total locked tracking
        s_totalLocked -= _slashAmount;
        locked.lockedAmount = remainingAmount;

        // Initiate the unlock process
        _initiateUnlock(_validator, locked);

        // Burn the slashed tokens
        if (_slashAmount > 0) {
            _burn(address(this), _slashAmount);
            emit SlashedTokensBurned(_slashAmount);
        }

        emit ValidatorSlashed(_validator, _slashAmount, remainingAmount);
    }

    // ============ Token Locking for Validators ============

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

        uint256 lockAmount = _isValidator
            ? s_validatorLockAmount
            : s_userLockAmount;

        if (balanceOf(_user) < lockAmount) {
            revert Token__InsufficientBalance();
        }

        LockedTokens storage locked = s_lockedTokens[_user];
        if (locked.locked) revert Token__AlreadyLocked();

        locked.locked = true;
        locked.isValidator = _isValidator;
        locked.lockedAmount = lockAmount;

        // Update total locked tracking
        s_totalLocked += lockAmount;

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
            uint256 lockAmount = locked.lockedAmount;

            // Update total locked tracking
            s_totalLocked -= lockAmount;

            delete s_lockedTokens[_user];
            _transfer(address(this), _user, lockAmount);
            emit TokensUnlocked(_user, locked.isValidator, lockAmount);
        } else {
            // If locked is true, initiate the unlock process
            _initiateUnlock(_user, locked);
        }
    }

    function _initiateUnlock(
        address _user,
        LockedTokens storage locked
    ) internal {
        locked.locked = false;
        locked.unlockTime = uint128(block.timestamp);
        emit UnlockInitiated(_user, locked.unlockTime);
    }

    /**
     * @notice Escrow payment for a job
     * @param _user The address of the user receiving the payment
     * @param _payment The amount of payment to be escrowed
     */
    function escrowPayment(
        address _user,
        uint256 _payment
    ) external onlySmartnodesCore {
        if (_user == address(0)) {
            revert Token__InvalidAddress();
        }
        if (_payment == 0 || balanceOf(_user) < _payment) {
            revert Token__InsufficientBalance();
        }

        // Transfer payment to the contract
        _transfer(_user, address(this), _payment);

        // Update individual and total escrowed amounts
        s_escrowedPayments[_user].sno += uint128(_payment);
        s_totalEscrowed.sno += uint128(_payment);

        emit PaymentEscrowed(_user, _payment);
    }

    /**
     * @notice Escrow ETH payment for a job
     * @param _user The address of the user making the payment
     * @param _payment The amount of ETH payment to be escrowed
     */
    function escrowEthPayment(
        address _user,
        uint256 _payment
    ) external payable onlySmartnodesCore {
        if (_user == address(0)) {
            revert Token__InvalidAddress();
        }
        if (_payment == 0 || msg.value < _payment) {
            revert Token__InsufficientBalance();
        }

        // Update individual and total escrowed amounts
        s_escrowedPayments[_user].eth += uint128(_payment);
        s_totalEscrowed.eth += uint128(_payment);

        emit EthPaymentEscrowed(_user, _payment);
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

        // Update individual and total escrowed amounts
        s_escrowedPayments[_user].sno -= uint128(_amount);
        s_totalEscrowed.sno -= uint128(_amount);

        emit EscrowReleased(_user, _amount);
    }

    /**
     * @notice Release escrowed ETH payment for reward distribution
     * @param _user The address of the user whose escrowed ETH payment is being released
     * @param _amount The amount of escrowed ETH payment to be released
     * @dev This releases the escrowed ETH to be available for distribution as rewards
     * @dev The ETH stays in the contract but is no longer considered escrowed
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

        // Update individual and total escrowed amounts
        s_escrowedPayments[_user].eth -= uint128(_amount);
        s_totalEscrowed.eth -= uint128(_amount);

        emit EthEscrowReleased(_user, _amount);
    }

    // ============ View Functions ============

    /**
     * @dev Check if user has locked tokens
     */
    function isLocked(address user) external view returns (bool) {
        return s_lockedTokens[user].locked;
    }

    /**
     * @dev Get user's lock information
     */
    function getLockInfo(
        address user
    )
        external
        view
        returns (
            bool locked,
            bool isValidator,
            uint256 timestamp,
            uint256 lockAmount
        )
    {
        LockedTokens storage lock = s_lockedTokens[user];

        return (
            lock.locked,
            lock.isValidator,
            lock.unlockTime,
            lock.lockedAmount
        );
    }

    /**
     * @dev Get escrowed payments for a specific address
     */
    function getEscrowedPayments(
        address _user
    ) external view returns (PaymentAmounts memory) {
        return s_escrowedPayments[_user];
    }

    /**
     * @notice Get supply breakdown
     */
    function getSupplyBreakdown()
        external
        view
        returns (
            uint256 _totalSupply,
            uint256 _circulating,
            uint256 _locked,
            uint256 _unclaimed,
            uint256 _escrowed,
            uint256 _stateTime,
            uint256 _stateReward
        )
    {
        uint256 total = totalSupply();
        uint256 reward = getEmissionRate();

        return (
            total,
            total - s_totalLocked - s_totalUnclaimed.sno - s_totalEscrowed.sno,
            s_totalLocked,
            s_totalUnclaimed.sno,
            s_totalEscrowed.sno,
            s_distributionInterval,
            reward
        );
    }

    /**
     * @notice Get ETH breakdown
     */
    function getEthBreakdown() external view returns (EthBreakdown memory) {
        uint256 contractEth = address(this).balance;
        return
            EthBreakdown({
                totalContractEth: contractEth,
                unclaimedEth: s_totalUnclaimed.eth,
                escrowedEth: s_totalEscrowed.eth,
                availableEth: contractEth -
                    s_totalUnclaimed.eth -
                    s_totalEscrowed.eth
            });
    }

    /**
     * @dev Get the current SmartnodesCore contract address
     */
    function getSmartnodesCore() external view returns (address) {
        return address(s_smartnodesCore);
    }

    // ============ Required Overrides ============
    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

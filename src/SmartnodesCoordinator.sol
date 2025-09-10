// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";
import {ISmartnodesToken} from "./interfaces/ISmartnodesToken.sol";

/**
 * @title SmartnodesCoordinator
 * @notice Manages job and user participation updates to SmartnodesCore contract. Updates are
 * @notice controlled by a rotating set of validators that vote on these state updates periodically.
 */
contract SmartnodesCoordinator is ReentrancyGuard {
    // ============= Errors ==============
    error Coordinator__NotValidator();
    error Coordinator__NotCoreContract();
    error Coordinator__NotTokenContract();
    error Coordinator__NotEligibleValidator();
    error Coordinator__AlreadySubmittedProposal();
    error Coordinator__AlreadyVoted();
    error Coordinator__InvalidProposalNumber();
    error Coordinator__ProposalTooEarly();
    error Coordinator__NotEnoughVotes();
    error Coordinator__ProposalDataMismatch();
    error Coordinator__MustBeProposalCreator();
    error Coordinator__ValidatorAlreadyExists();
    error Coordinator__ValidatorNotRegistered();
    error Coordinator__NotEnoughActiveValidators();
    error Coordinator__InvalidApprovalPercentage();
    error Coordinator__InvalidAddress();

    // ============= State Variables ==============
    ISmartnodesCore private immutable i_smartnodesCore;
    ISmartnodesToken private immutable i_smartnodesToken;
    uint8 private immutable i_requiredApprovalsPercentage;

    // Packed time-related variables
    struct TimeConfig {
        uint128 updateTime;
        uint128 lastExecutionTime;
    }
    TimeConfig public timeConfig;

    // Packed proposal info
    struct Proposal {
        address creator;
        uint8 proposalNum;
        uint32 votes;
        bytes32 proposalHash;
    }

    uint256 public nextProposalId;

    // Validator management
    address[] public validators;
    address[] public currentRoundValidators;
    Proposal[] public currentProposals;
    mapping(address => bool) public isValidator;
    mapping(address => uint256) public validatorVote;
    mapping(address => uint8) public hasSubmittedProposal;
    mapping(address => uint256) public validatorLastActiveRound; // Track validator activity

    // Enhanced round management
    uint256 public currentRoundNumber;
    uint256 private roundSeed; // Used for deterministic but unpredictable validator selection

    // ============= Events ==============
    event ProposalCreated(
        uint256 indexed proposalId,
        bytes32 indexed proposalHash,
        address indexed creator
    );
    event ProposalExecuted(
        uint256 indexed proposalId,
        bytes32 indexed proposalHash
    );
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event ConfigUpdated(uint256 updateTime);
    event NewRoundStarted(
        uint256 indexed roundNumber,
        address[] selectedValidators
    );

    // ============= Modifiers ==============
    modifier onlyValidator() {
        if (!isValidator[msg.sender]) revert Coordinator__NotValidator();
        _;
    }

    modifier onlySmartnodesCore() {
        if (msg.sender != address(i_smartnodesCore))
            revert Coordinator__NotCoreContract();
        _;
    }

    modifier onlySmartnodesToken() {
        if (msg.sender != address(i_smartnodesToken))
            revert Coordinator__NotTokenContract();
        _;
    }

    modifier onlyEligibleValidator() {
        bool isSelectedValidator = _isCurrentRoundValidator(msg.sender);
        bool roundExpired = _isCurrentRoundExpired();

        if (
            !isSelectedValidator && !(isValidator[msg.sender] && roundExpired)
        ) {
            revert Coordinator__NotEligibleValidator();
        }

        if (roundExpired) {
            _cleanupExpiredRound();
        }
        _;
    }

    constructor(
        uint128 _updateTime,
        uint8 _requiredApprovalsPercentage,
        address _smartnodesCore,
        address _smartnodesToken,
        address[] memory _genesisNodes
    ) {
        if (
            _requiredApprovalsPercentage == 0 ||
            _requiredApprovalsPercentage > 100
        ) {
            revert Coordinator__InvalidApprovalPercentage();
        }
        if (_smartnodesCore == address(0)) {
            revert Coordinator__InvalidAddress();
        }

        i_smartnodesCore = ISmartnodesCore(_smartnodesCore);
        i_smartnodesToken = ISmartnodesToken(_smartnodesToken);
        i_requiredApprovalsPercentage = _requiredApprovalsPercentage;

        timeConfig = TimeConfig({
            updateTime: _updateTime,
            lastExecutionTime: 0 // This allows the first proposal to be submitted by any validator
        });

        // Initialize validators from genesis nodes
        for (uint256 i = 0; i < _genesisNodes.length; i++) {
            if (_genesisNodes[i] != address(0)) {
                _addValidator(_genesisNodes[i]);
            }
        }

        // Initialize round management
        currentRoundNumber = 1;
        roundSeed = uint256(
            keccak256(
                abi.encode(block.timestamp, block.prevrandao, _genesisNodes)
            )
        );

        // Select initial round validators
        _selectNewRoundValidators();
        nextProposalId = 1;
    }

    // ============= Core Functions ==============
    /**
     * @notice Creates a new proposal represented by a hash of all the essential data to update from the aggregated off-chain state.
     */
    function createProposal(
        bytes32 proposalHash
    ) external onlyEligibleValidator nonReentrant {
        address sender = msg.sender;
        TimeConfig memory tc = timeConfig;

        // Allow proposals only after 'updateTime' has passed since last executed proposal
        if (block.timestamp < tc.lastExecutionTime + tc.updateTime) {
            revert Coordinator__ProposalTooEarly();
        }

        // Check if validator already has a proposal this round
        bool hasExistingProposal = false;
        uint256 proposalLength = currentProposals.length;

        for (uint8 i = 0; i < proposalLength; i++) {
            if (currentProposals[i].creator == sender) {
                hasExistingProposal = true;
                break;
            }
        }

        if (hasExistingProposal) {
            revert Coordinator__AlreadySubmittedProposal();
        }

        uint8 proposalNum = uint8(proposalLength) + 1; // +1 to distinguish from 0 (no proposal)

        // Create new proposal
        currentProposals.push(
            Proposal({
                creator: sender,
                proposalNum: proposalNum,
                votes: 0,
                proposalHash: proposalHash
            })
        );

        // mark as active
        hasSubmittedProposal[sender] = proposalNum;
        validatorLastActiveRound[sender] = currentRoundNumber;

        emit ProposalCreated(proposalNum, proposalHash, sender);
    }

    /**
     * @notice Vote for a proposal
     * @param proposalId current round proposal ID
     */
    function voteForProposal(
        uint8 proposalId
    ) external onlyValidator nonReentrant {
        if (proposalId > currentProposals.length) {
            revert Coordinator__InvalidProposalNumber();
        }

        if (validatorVote[msg.sender] != 0) {
            revert Coordinator__AlreadyVoted();
        }

        Proposal storage proposal = currentProposals[proposalId - 1];
        validatorVote[msg.sender] = proposalId;
        validatorLastActiveRound[msg.sender] = currentRoundNumber; // Mark as active
        proposal.votes++;
    }

    /**
     * @notice Execute a proposal with comprehensive validation if enough votes are received
     * @param proposalId current round proposal ID
     * @param totalCapacity total capacity for each worker measured in resources/time (ie GB/hr)
     * @param validatorsToRemove any inactive validators that were not found on P2P
     * @param jobHashes job IDs to be completed
     */
    function executeProposal(
        uint8 proposalId,
        bytes32 merkleRoot,
        uint256 totalCapacity,
        address[] calldata validatorsToRemove,
        bytes32[] calldata jobHashes,
        bytes32 workersHash,
        bytes32 capacitiesHash
    ) external onlyValidator nonReentrant {
        if (proposalId == 0 || proposalId > currentProposals.length) {
            revert Coordinator__InvalidProposalNumber();
        }

        Proposal storage proposal = currentProposals[proposalId - 1];

        // Cache frequently accessed storage variables
        address creator = proposal.creator;
        uint96 votes = proposal.votes;
        bytes32 storedHash = proposal.proposalHash;

        // Batch validation with cached values
        if (creator != msg.sender) {
            revert Coordinator__MustBeProposalCreator();
        }
        if (votes < _calculateRequiredVotes()) {
            revert Coordinator__NotEnoughVotes();
        }

        // Verify proposal data integrity
        bytes32 computedHash = _computeProposalHash(
            proposalId,
            merkleRoot,
            validatorsToRemove,
            jobHashes,
            workersHash,
            capacitiesHash
        );

        if (computedHash != storedHash) {
            revert Coordinator__ProposalDataMismatch();
        }

        // Mark executor as active
        validatorLastActiveRound[msg.sender] = currentRoundNumber;

        // Optimized batch validator removal
        if (validatorsToRemove.length > 0) {
            _removeValidatorsBatchOptimized(validatorsToRemove);
        }

        // Build approved validators list with pre-sized array
        address[] memory approvedValidators = _buildApprovedValidatorsList(
            proposalId
        );

        emit ProposalExecuted(proposalId, storedHash);
        _updateRound();

        // Update core contract
        i_smartnodesCore.updateContract(
            jobHashes,
            merkleRoot,
            totalCapacity,
            approvedValidators,
            msg.sender
        );
    }

    // ============= Validator Management =============
    /**
     * @notice Add validator with stake verification
     */
    function addValidator() external {
        _addValidator(msg.sender);
    }

    /**
     * @notice Remove own validator registration
     */
    function removeValidator() external onlyValidator {
        _removeValidator(msg.sender);
    }

    // ============= ADMIN FUNCTIONS =============
    /**
     * @notice Change proposal creation timeframes
     */
    function updateTiming(uint256 _newInterval) external onlySmartnodesToken {
        timeConfig.updateTime = uint128(_newInterval);
        emit ConfigUpdated(_newInterval);
    }

    // ============= INTERNAL FUNCTIONS =============
    function _addValidator(address validator) internal {
        if (!i_smartnodesCore.isLockedValidator(validator)) {
            revert Coordinator__NotValidator();
        }
        if (isValidator[validator]) {
            revert Coordinator__ValidatorAlreadyExists();
        }

        validators.push(validator);
        isValidator[validator] = true;
        validatorLastActiveRound[validator] = currentRoundNumber; // Mark as active from start
        emit ValidatorAdded(validator);
    }

    function _removeValidator(address validator) internal {
        if (!isValidator[validator]) {
            revert Coordinator__ValidatorNotRegistered();
        }

        isValidator[validator] = false;
        validatorVote[validator] = 0; // Clear vote
        delete validatorLastActiveRound[validator]; // Clear activity tracking

        // Remove from validators array
        address[] storage vals = validators;
        uint256 length = vals.length;

        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (vals[i] == validator) {
                    vals[i] = vals[length - 1];
                    vals.pop();
                    break;
                }
            }
        }

        emit ValidatorRemoved(validator);
    }

    function _removeValidatorsBatchOptimized(
        address[] calldata validatorsToRemove
    ) internal {
        uint256 length = validatorsToRemove.length;

        address[] storage vals = validators;
        uint256 validatorCount = vals.length;

        for (uint256 i = 0; i < length; ) {
            address validator = validatorsToRemove[i];
            if (isValidator[validator]) {
                isValidator[validator] = false;
                validatorVote[validator] = 0;
                delete validatorLastActiveRound[validator];

                // Find and remove from array efficiently
                for (uint256 j = 0; j < validatorCount; ) {
                    if (vals[j] == validator) {
                        vals[j] = vals[validatorCount - 1];
                        vals.pop();
                        --validatorCount;
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
                emit ValidatorRemoved(validator);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate required votes as >50% of total active validators
     * @dev This ensures true majority consensus
     */
    function _calculateRequiredVotes() internal view returns (uint256) {
        uint256 validatorCount = validators.length;
        if (validatorCount == 0) return 0;

        // Require >50% (strict majority)
        return (validatorCount / 2) + 1;
    }

    /**
     * @notice Determine how many validators should be selected for the round
     * @dev Returns 1-5 validators based on total validator count
     */
    function _calculateRoundValidatorCount() internal view returns (uint256) {
        uint256 totalValidators = validators.length;

        if (totalValidators < 2) return 1;
        if (totalValidators < 5) return 2;
        if (totalValidators < 10) return 3;
        return 5;
    }

    function _cleanupExpiredRound() internal {
        _resetValidatorStates();
        delete currentProposals;
    }

    function _updateRound() internal {
        _resetValidatorStates();
        currentRoundNumber++;
        _selectNewRoundValidators();
        delete currentProposals; // Clear proposals for new round
        timeConfig.lastExecutionTime = uint128(block.timestamp);
        nextProposalId++;
    }

    function _resetValidatorStates() internal {
        address[] memory vals = validators;
        uint256 validatorCount = vals.length;

        unchecked {
            for (uint256 i = 0; i < validatorCount; ++i) {
                address val = vals[i];
                delete validatorVote[val];
                delete hasSubmittedProposal[val];
            }
        }
    }

    /**
     * @notice Enhanced validator selection with better randomization and activity tracking
     * @dev Uses Fisher-Yates shuffle algorithm for fair, unbiased selection
     */
    function _selectNewRoundValidators() internal {
        uint256 validatorCount = validators.length;

        if (validatorCount == 0) {
            delete currentRoundValidators;
            return;
        }

        uint256 requiredValidators = _calculateRoundValidatorCount();

        if (validatorCount < requiredValidators) {
            // If we don't have enough validators, select all of them
            requiredValidators = validatorCount;
        }

        delete currentRoundValidators;

        // Create a working copy of validators for shuffling
        address[] memory shuffleArray = new address[](validatorCount);
        for (uint256 i = 0; i < validatorCount; i++) {
            shuffleArray[i] = validators[i];
        }

        // Update seed for this round using multiple entropy sources
        roundSeed = uint256(
            keccak256(
                abi.encode(
                    roundSeed,
                    block.timestamp,
                    block.prevrandao,
                    currentRoundNumber,
                    blockhash(block.number - 1)
                )
            )
        );

        // Fisher-Yates shuffle to randomize validator order
        for (uint256 i = validatorCount; i > 1; i--) {
            roundSeed = uint256(keccak256(abi.encode(roundSeed, i)));
            uint256 j = roundSeed % i;

            // Swap elements
            address temp = shuffleArray[j];
            shuffleArray[j] = shuffleArray[i - 1];
            shuffleArray[i - 1] = temp;
        }

        // Prioritize active validators (those who participated in recent rounds)
        uint256 selectedCount = 0;
        uint256 inactivityThreshold = currentRoundNumber > 3
            ? currentRoundNumber - 3
            : 0;

        // First, try to select active validators
        for (
            uint256 i = 0;
            i < validatorCount && selectedCount < requiredValidators;
            i++
        ) {
            address validator = shuffleArray[i];
            if (validatorLastActiveRound[validator] > inactivityThreshold) {
                currentRoundValidators.push(validator);
                selectedCount++;
            }
        }

        // If we still need more validators, select from remaining ones
        for (
            uint256 i = 0;
            i < validatorCount && selectedCount < requiredValidators;
            i++
        ) {
            address validator = shuffleArray[i];
            if (validatorLastActiveRound[validator] <= inactivityThreshold) {
                // Check if not already selected
                bool alreadySelected = false;
                for (uint256 j = 0; j < currentRoundValidators.length; j++) {
                    if (currentRoundValidators[j] == validator) {
                        alreadySelected = true;
                        break;
                    }
                }

                if (!alreadySelected) {
                    currentRoundValidators.push(validator);
                    selectedCount++;
                }
            }
        }

        emit NewRoundStarted(currentRoundNumber, currentRoundValidators);
    }

    function _computeProposalHash(
        uint8 proposalId,
        bytes32 merkleRoot,
        address[] calldata validatorsToRemove,
        bytes32[] calldata jobHashes,
        bytes32 workersHash,
        bytes32 capacitiesHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    proposalId,
                    merkleRoot,
                    validatorsToRemove,
                    jobHashes,
                    workersHash,
                    capacitiesHash
                )
            );
    }

    function _isCurrentRoundValidator(
        address validator
    ) internal view returns (bool) {
        address[] memory selected = currentRoundValidators;
        uint256 length = selected.length;

        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (selected[i] == validator) return true;
            }
        }
        return false;
    }

    function _buildApprovedValidatorsList(
        uint256 proposalId
    ) internal view returns (address[] memory approvedValidators) {
        address[] memory vals = validators;
        uint256 validatorCount = vals.length;

        // Count approved validators
        uint256 approvedCount;
        for (uint256 i = 0; i < validatorCount; ) {
            if (validatorVote[vals[i]] == proposalId) {
                unchecked {
                    ++approvedCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Allocate exact size array
        approvedValidators = new address[](approvedCount);

        // Populate array
        uint256 index;
        for (uint256 i = 0; i < validatorCount; ) {
            address validator = vals[i];
            if (validatorVote[validator] == proposalId) {
                approvedValidators[index] = validator;
                unchecked {
                    ++index;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _isCurrentRoundExpired() internal view returns (bool) {
        TimeConfig memory tc = timeConfig;
        return block.timestamp > tc.lastExecutionTime + (tc.updateTime << 1);
    }

    // ============= View Functions =============
    function isProposalReady(uint8 proposalId) external view returns (bool) {
        if (proposalId == 0 || proposalId > currentProposals.length) {
            revert Coordinator__InvalidProposalNumber();
        }

        Proposal storage proposal = currentProposals[proposalId - 1];
        return (proposal.votes >= _calculateRequiredVotes());
    }

    function isRoundExpired() external view returns (bool) {
        return _isCurrentRoundExpired();
    }

    function getRequiredApprovals() external view returns (uint256) {
        return _calculateRequiredVotes();
    }

    function getValidatorCount() external view returns (uint256) {
        return validators.length;
    }

    function getCurrentRoundValidators()
        external
        view
        returns (address[] memory)
    {
        return currentRoundValidators;
    }

    function getValidators() external view returns (address[] memory) {
        return validators;
    }

    function getCurrentProposals() external view returns (Proposal[] memory) {
        return currentProposals;
    }

    function getNumProposals() public view returns (uint8) {
        return uint8(currentProposals.length);
    }

    function getProposal(
        uint8 proposalId
    ) external view returns (Proposal memory) {
        uint256 proposalLength = getNumProposals();
        if (proposalId == 0 || proposalId > proposalLength) {
            revert Coordinator__InvalidProposalNumber();
        }
        return currentProposals[proposalId - 1];
    }

    function getState()
        external
        view
        returns (
            uint256 proposalId,
            uint256 executionTime,
            address[] memory roundValidators
        )
    {
        TimeConfig memory tc = timeConfig;
        return (nextProposalId, tc.lastExecutionTime, currentRoundValidators);
    }

    /**
     * @notice Get validator activity information
     */
    function getValidatorActivity(
        address validator
    )
        external
        view
        returns (uint256 lastActiveRound, bool isCurrentlySelected)
    {
        return (
            validatorLastActiveRound[validator],
            _isCurrentRoundValidator(validator)
        );
    }

    /**
     * @notice Get current round information
     */
    function getCurrentRoundInfo()
        external
        view
        returns (
            uint256 roundNumber,
            uint256 selectedValidatorCount,
            uint256 requiredValidatorCount,
            uint256 requiredVotes
        )
    {
        return (
            currentRoundNumber,
            currentRoundValidators.length,
            _calculateRoundValidatorCount(),
            _calculateRequiredVotes()
        );
    }
}

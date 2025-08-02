// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";

/**
 * @title SmartnodesCoordinator
 * @notice Manages job and user participation updates to SmartnodesCore contract. Updates are
 * @notice controlled by a rotating set of validators that vote on these state updates periodically.
 */
contract SmartnodesCoordinator is ReentrancyGuard {
    // ============= Errors ==============
    error Coordinator__NotValidator();
    error Coordinator__NotCoreContract();
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
    error Coordinator__ProposalExpired();

    // ============= Structs ==============
    struct Proposal {
        bytes32 hash;
        address creator;
        uint16 votes;
        uint32 createdAt;
        bool executed;
    }

    // ============= State Variables ==============
    ISmartnodesCore private immutable i_smartnodesCore;
    uint8 private immutable i_requiredApprovalsPercentage;

    // Pack time-related variables
    struct TimeConfig {
        uint128 updateTime;
        uint128 lastExecutionTime;
    }
    TimeConfig public timeConfig;

    // Pack round data
    struct RoundData {
        uint128 currentRoundId;
        uint128 nextProposalId;
    }
    RoundData public roundData;

    uint256 public requiredValidators;

    // Proposal cleanup configuration
    uint256 public constant MAX_PROPOSAL_AGE = 7 days; // Proposals older than 7 days can be cleaned up
    uint256 public constant CLEANUP_BATCH_SIZE = 50; // Max proposals to clean in one call
    uint256 public oldestProposalId = 1; // Track oldest proposal for efficient cleanup

    // Validator management
    address[] public validators;
    address[] public currentRoundValidators;

    mapping(address => bool) public isValidator;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public validatorToProposal;
    mapping(address => uint256) public validatorVote;
    mapping(uint256 => uint256) private proposalReadyBitmap;

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
    event ProposalExpired(uint256 indexed proposalId);
    event ProposalsCleanedUp(uint256 fromId, uint256 toId, uint256 count);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event RoundStarted(uint256 indexed roundId, address[] selectedValidators);
    event ConfigUpdated(uint256 updateTime);

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
        } else if (validatorToProposal[msg.sender] != 0) {
            revert Coordinator__AlreadySubmittedProposal();
        }
        _;
    }

    modifier validProposal(uint256 proposalId) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.creator == address(0))
            revert Coordinator__InvalidProposalNumber();
        if (proposal.executed) revert Coordinator__InvalidProposalNumber();
        if (_isProposalExpired(proposalId))
            revert Coordinator__ProposalExpired();
        _;
    }

    constructor(
        uint128 _updateTime,
        uint8 _requiredApprovalsPercentage,
        address _smartnodesCore,
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
        i_requiredApprovalsPercentage = _requiredApprovalsPercentage;

        timeConfig = TimeConfig({
            updateTime: _updateTime,
            lastExecutionTime: 0 // This is set to 0, which allows the first proposal to be submitted by any validator
        });
        currentRoundValidators = _genesisNodes;
        roundData = RoundData({currentRoundId: 1, nextProposalId: 1});
    }

    // ============= Core Functions ==============
    /**
     * @notice Creates a new proposal represented by a hash of all the essential data to update from the aggregated off-chain state.
     */
    function createProposal(
        bytes32 proposalHash
    ) external onlyEligibleValidator nonReentrant {
        TimeConfig memory tc = timeConfig;

        if (block.timestamp < tc.lastExecutionTime + tc.updateTime) {
            revert Coordinator__ProposalTooEarly();
        }

        RoundData memory rd = roundData;
        uint256 proposalId = rd.nextProposalId;

        // Update round data
        roundData.nextProposalId = uint128(proposalId + 1);

        proposals[proposalId] = Proposal({
            hash: proposalHash,
            creator: msg.sender,
            votes: 0,
            createdAt: uint32(block.timestamp),
            executed: false
        });

        validatorToProposal[msg.sender] = proposalId;
        emit ProposalCreated(proposalId, proposalHash, msg.sender);
    }

    /**
     * @notice Vote for a proposal
     * @param proposalId current round proposal ID
     */
    function voteForProposal(
        uint256 proposalId
    ) external onlyValidator validProposal(proposalId) nonReentrant {
        if (!_isCurrentRoundExpired() && validatorVote[msg.sender] != 0) {
            revert Coordinator__AlreadyVoted();
        }

        // Auto-add validator if eligible
        if (!isValidator[msg.sender]) {
            _tryAddValidator(msg.sender);
        }

        validatorVote[msg.sender] = proposalId;

        // Increment votes and check threshold in one go
        Proposal storage proposal = proposals[proposalId];
        uint16 newVotes = ++proposal.votes;
        uint256 requiredVotes = _calculateRequiredVotes();

        if (newVotes >= requiredVotes) {
            _setProposalReady(proposalId);
        }
    }

    /**
     * @notice Execute a proposal with comprehensive validation if enough votes are received
     * @param proposalId current round proposal ID
     * @param validatorsToRemove any inactive validators that were not found on P2P
     * @param jobHashes job IDs to be completed
     * @param jobWorkers worker addresses associated with completed jobs
     * @param jobCapacities job capacity for each worker measured in resources/time (ie GB/hr)
     */
    function executeProposal(
        uint256 proposalId,
        address[] calldata validatorsToRemove,
        bytes32[] calldata jobHashes,
        address[] calldata jobWorkers,
        uint256[] calldata jobCapacities
    ) external onlyValidator validProposal(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];

        // Batch validation
        if (proposal.creator != msg.sender)
            revert Coordinator__MustBeProposalCreator();
        if (proposal.votes < _calculateRequiredVotes())
            revert Coordinator__NotEnoughVotes();

        // Verify proposal data integrity
        bytes32 computedHash = _computeProposalHash(
            validatorsToRemove,
            jobHashes,
            jobCapacities,
            jobWorkers,
            proposal.createdAt
        );
        if (computedHash != proposal.hash)
            revert Coordinator__ProposalDataMismatch();

        // Mark as executed before external calls
        proposal.executed = true;

        // Batch validator removal
        if (validatorsToRemove.length > 0) {
            _removeValidatorsBatch(validatorsToRemove);
        }

        // Build approved validators list
        address[] memory approvedValidators = _buildApprovedValidatorsList(
            proposalId
        );

        // Single external call to core contract (saves gas vs multiple calls)
        i_smartnodesCore.updateContract(
            jobHashes,
            approvedValidators,
            jobWorkers,
            jobCapacities
        );

        emit ProposalExecuted(proposalId, proposal.hash);
        _updateRound();
    }

    // ============= Cleanup Functions =============
    /**
     * @notice Clean up old proposals to save storage costs
     * @dev Can be called by anyone to incentivize cleanup
     * @return cleanedCount Number of proposals cleaned up
     */
    function cleanupOldProposals() external returns (uint256 cleanedCount) {
        return _cleanupProposals(CLEANUP_BATCH_SIZE);
    }

    /**
     * @notice Force expire a specific proposal that's older than MAX_PROPOSAL_AGE
     * @param proposalId The proposal to expire
     */
    function expireProposal(uint256 proposalId) external {
        if (!_isProposalExpired(proposalId))
            revert Coordinator__ProposalTooEarly();

        Proposal storage proposal = proposals[proposalId];
        if (proposal.creator == address(0))
            revert Coordinator__InvalidProposalNumber();
        if (proposal.executed) return; // Already handled

        delete proposals[proposalId];
        emit ProposalExpired(proposalId);
    }

    // ============= Validator Management =============
    /**
     * @notice Add validator with stake verification
     */
    function addValidator(address validator) external {
        _addValidator(validator);
    }

    /**
     * @notice Remove own validator registration
     */
    function removeValidator() external onlyValidator {
        _removeValidator(msg.sender);
    }

    // ============= ADMIN FUNCTIONS =============
    /**
     * @notice Half update configuration parameters to allow double to proposal creation times
     */
    function halfStateTime() external onlySmartnodesCore {
        TimeConfig memory tc = timeConfig;
        uint128 newUpdateTime = tc.updateTime / 2;

        timeConfig.updateTime = newUpdateTime;
        emit ConfigUpdated(newUpdateTime);
    }

    // ============= INTERNAL FUNCTIONS =============
    function _cleanupProposals(
        uint256 batchSize
    ) internal returns (uint256 cleanedCount) {
        uint256 currentProposalId = roundData.nextProposalId;
        uint256 startId = oldestProposalId;
        uint256 endId = startId + batchSize;

        if (endId > currentProposalId) {
            endId = currentProposalId;
        }

        if (startId >= endId) return 0;

        uint256 cutoffTime = block.timestamp - MAX_PROPOSAL_AGE;

        unchecked {
            for (uint256 i = startId; i < endId; ++i) {
                Proposal storage proposal = proposals[i];

                // Skip if proposal doesn't exist
                if (proposal.creator == address(0)) {
                    continue;
                } else if (proposal.createdAt > cutoffTime) {
                    break;
                }

                // Clean up executed or expired proposals
                if (proposal.executed || _isProposalExpired(i)) {
                    delete proposals[i];
                    ++cleanedCount;
                }
            }
        }

        // Update oldest proposal pointer
        oldestProposalId = endId;

        if (cleanedCount > 0) {
            emit ProposalsCleanedUp(startId, endId - 1, cleanedCount);
        }

        return cleanedCount;
    }

    function _isProposalExpired(
        uint256 proposalId
    ) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.creator == address(0)) return false;

        return block.timestamp > proposal.createdAt + MAX_PROPOSAL_AGE;
    }

    function _addValidator(address validator) internal {
        if (!i_smartnodesCore.isLockedValidator(validator)) {
            revert Coordinator__NotValidator();
        }
        if (isValidator[validator])
            revert Coordinator__ValidatorAlreadyExists();

        validators.push(validator);
        isValidator[validator] = true;
        emit ValidatorAdded(validator);
    }

    function _tryAddValidator(address validator) internal {
        if (
            !isValidator[validator] &&
            i_smartnodesCore.isLockedValidator(validator)
        ) {
            validators.push(validator);
            isValidator[validator] = true;
            emit ValidatorAdded(validator);
        }
    }

    function _removeValidator(address validator) internal {
        if (!isValidator[validator])
            revert Coordinator__ValidatorNotRegistered();

        isValidator[validator] = false;

        // More efficient array removal using unchecked arithmetic
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

    function _removeValidatorsBatch(
        address[] calldata validatorsToRemove
    ) internal {
        uint256 length = validatorsToRemove.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                _removeValidator(validatorsToRemove[i]);
            }
        }
    }

    function _calculateRequiredVotes() internal view returns (uint256) {
        uint256 validatorCount = validators.length;
        return (validatorCount * i_requiredApprovalsPercentage + 99) / 100;
    }

    function _cleanupExpiredRound() internal {
        _resetValidatorStates();

        // Enhanced cleanup: also clean up old proposals during round expiry
        _cleanupProposals(CLEANUP_BATCH_SIZE / 2); // Use smaller batch during round transitions

        emit ProposalExpired(roundData.currentRoundId);
    }

    function _updateRound() internal {
        _resetValidatorStates();
        _selectNewRoundValidators();

        RoundData memory rd = roundData;

        timeConfig.lastExecutionTime = uint128(block.timestamp);
        roundData.currentRoundId = rd.currentRoundId + 1;
    }

    function _resetValidatorStates() internal {
        address[] memory vals = validators;
        address[] memory currentVals = currentRoundValidators;

        uint256 validatorCount = vals.length;
        uint256 selectedCount = currentVals.length;

        unchecked {
            for (uint256 i = 0; i < validatorCount; ++i) {
                delete validatorVote[vals[i]];
            }
            for (uint256 i = 0; i < selectedCount; ++i) {
                delete validatorToProposal[currentVals[i]];
            }
        }
    }

    function _selectNewRoundValidators() internal {
        uint256 validatorCount = validators.length;
        if (validatorCount < requiredValidators)
            revert Coordinator__NotEnoughActiveValidators();

        delete currentRoundValidators;

        // More efficient validator selection
        uint256 seed = uint256(
            keccak256(abi.encode(block.timestamp, roundData.currentRoundId))
        );
        uint256 selectedCount = 0;
        uint256 maxSelections = requiredValidators < validatorCount
            ? requiredValidators
            : validatorCount;

        while (selectedCount < maxSelections) {
            seed = uint256(keccak256(abi.encode(seed)));
            uint256 randIndex = seed % validatorCount;
            address selectedValidator = validators[randIndex];

            // Check if already selected (more efficient than nested loop for small arrays)
            bool alreadySelected = false;
            address[] memory selected = currentRoundValidators;
            unchecked {
                for (uint256 j = 0; j < selectedCount; ++j) {
                    if (selected[j] == selectedValidator) {
                        alreadySelected = true;
                        break;
                    }
                }
            }

            if (!alreadySelected) {
                currentRoundValidators.push(selectedValidator);
                ++selectedCount;
            }
        }

        emit RoundStarted(roundData.currentRoundId, currentRoundValidators);
    }

    function _buildApprovedValidatorsList(
        uint256 proposalId
    ) internal view returns (address[] memory) {
        address[] memory vals = validators;
        uint256 validatorCount = vals.length;

        // Pre-allocate with maximum possible size
        address[] memory approvedValidators = new address[](validatorCount);
        uint256 approvedCount = 0;

        unchecked {
            for (uint256 i = 0; i < validatorCount; ++i) {
                address validator = vals[i];
                if (validatorVote[validator] == proposalId) {
                    approvedValidators[approvedCount++] = validator;
                }
            }
        }

        // Resize array to actual count
        assembly {
            mstore(approvedValidators, approvedCount)
        }

        return approvedValidators;
    }

    function _computeProposalHash(
        address[] calldata validatorsToRemove,
        bytes32[] calldata jobHashes,
        uint256[] calldata jobCapacities,
        address[] calldata workers,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    validatorsToRemove,
                    jobHashes,
                    jobCapacities,
                    workers,
                    timestamp
                )
            );
    }

    function _setProposalReady(uint256 proposalId) internal {
        uint256 wordIndex = proposalId >> 8; // Equivalent to / 256 but cheaper
        uint256 bitIndex = proposalId & 255; // Equivalent to % 256 but cheaper
        proposalReadyBitmap[wordIndex] |= (1 << bitIndex);
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

    function _isCurrentRoundExpired() internal view returns (bool) {
        TimeConfig memory tc = timeConfig;
        return block.timestamp > tc.lastExecutionTime + (tc.updateTime << 1);
    }

    // ============= VIEW FUNCTIONS =============
    function isRoundExpired() external view returns (bool) {
        return _isCurrentRoundExpired();
    }

    function isProposalExpired(
        uint256 proposalId
    ) external view returns (bool) {
        return _isProposalExpired(proposalId);
    }

    function getRequiredApprovals() external view returns (uint256) {
        return _calculateRequiredVotes();
    }

    function isProposalReady(uint256 proposalId) external view returns (bool) {
        uint256 wordIndex = proposalId >> 8;
        uint256 bitIndex = proposalId & 255;
        return (proposalReadyBitmap[wordIndex] & (1 << bitIndex)) != 0;
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

    function getProposal(
        uint256 proposalId
    ) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getCleanupInfo()
        external
        view
        returns (uint256 oldestId, uint256 nextId, uint256 maxAge)
    {
        return (oldestProposalId, roundData.nextProposalId, MAX_PROPOSAL_AGE);
    }

    function getState()
        external
        view
        returns (
            uint256 roundId,
            uint256 proposalId,
            uint256 executionTime,
            address[] memory roundValidators
        )
    {
        RoundData memory rd = roundData;
        TimeConfig memory tc = timeConfig;

        return (
            rd.currentRoundId,
            rd.nextProposalId,
            tc.lastExecutionTime,
            currentRoundValidators
        );
    }
}

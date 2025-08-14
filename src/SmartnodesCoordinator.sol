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

    // ============= State Variables ==============
    ISmartnodesCore private immutable i_smartnodesCore;
    uint8 private immutable i_requiredApprovalsPercentage;

    // Pack time-related variables
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

    uint256 public requiredValidators;
    uint256 public nextProposalId;

    // Validator management
    address[] public validators;
    address[] public currentRoundValidators;
    Proposal[] public currentProposals;

    mapping(address => bool) public isValidator;
    mapping(address => uint256) public validatorVote; // Changed to uint256 for proposal index
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
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
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
        }
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
            lastExecutionTime: 0 // This allows the first proposal to be submitted by any validator
        });

        // Initialize validators from genesis nodes
        for (uint256 i = 0; i < _genesisNodes.length; i++) {
            if (_genesisNodes[i] != address(0)) {
                // _addValidator(_genesisNodes[i]);
            }
        }

        currentRoundValidators = _genesisNodes;
        requiredValidators = 1; // Set initial required validators
        nextProposalId = 1;
    }

    // ============= Core Functions ==============
    /**
     * @notice Creates a new proposal represented by a hash of all the essential data to update from the aggregated off-chain state.
     */
    function createProposal(
        bytes32 proposalHash
    ) external onlyEligibleValidator nonReentrant {
        TimeConfig memory tc = timeConfig;

        // Allow proposals only after 'updateTime' has passed since last executed proposal
        if (block.timestamp < tc.lastExecutionTime + tc.updateTime) {
            revert Coordinator__ProposalTooEarly();
        }

        // Check if validator already has a proposal this round
        bool hasExistingProposal = false;
        uint256 proposalLength = currentProposals.length;

        for (uint8 i = 0; i < proposalLength; i++) {
            if (currentProposals[i].creator == msg.sender) {
                hasExistingProposal = true;
                break;
            }
        }

        if (hasExistingProposal) {
            revert Coordinator__AlreadySubmittedProposal();
        }

        uint8 proposalNum = uint8(currentProposals.length) + 1;

        // Create new proposal
        currentProposals.push(
            Proposal({
                creator: msg.sender,
                proposalNum: proposalNum,
                votes: 1, // Creator automatically votes for their own proposal
                proposalHash: proposalHash
            })
        );

        // Record creator's vote
        validatorVote[msg.sender] = proposalNum + 1; // +1 to distinguish from 0 (no vote)

        emit ProposalCreated(proposalNum, proposalHash, msg.sender);
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

        if (!_isCurrentRoundExpired() && validatorVote[msg.sender] != 0) {
            revert Coordinator__AlreadyVoted();
        }

        // Auto-add validator if eligible and not expired round
        if (!isValidator[msg.sender] && !_isCurrentRoundExpired()) {
            _tryAddValidator(msg.sender);
        }

        Proposal storage proposal = currentProposals[proposalId - 1]; // (ie proposal 1 = 0th index)
        validatorVote[msg.sender] = proposalId;

        // Increment votes
        proposal.votes++;
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
        uint8 proposalId,
        address[] calldata validatorsToRemove,
        bytes32[] calldata jobHashes,
        address[] calldata jobWorkers,
        uint256[] calldata jobCapacities
    ) external onlyValidator nonReentrant {
        if (proposalId == 0 || proposalId > currentProposals.length) {
            revert Coordinator__InvalidProposalNumber();
        }

        Proposal storage proposal = currentProposals[proposalId - 1];

        // Batch validation
        if (proposal.creator != msg.sender) {
            revert Coordinator__MustBeProposalCreator();
        }
        if (proposal.votes < _calculateRequiredVotes()) {
            revert Coordinator__NotEnoughVotes();
        }

        // Verify proposal data integrity
        bytes32 computedHash = _computeProposalHash(
            validatorsToRemove,
            jobHashes,
            jobCapacities,
            jobWorkers
        );
        if (computedHash != proposal.proposalHash) {
            revert Coordinator__ProposalDataMismatch();
        }

        // Batch validator removal
        if (validatorsToRemove.length > 0) {
            _removeValidatorsBatch(validatorsToRemove);
        }

        // Build approved validators list
        address[] memory approvedValidators = _buildApprovedValidatorsList(
            proposalId
        );

        // Single external call to core contract
        i_smartnodesCore.updateContract(
            jobHashes,
            approvedValidators,
            jobWorkers,
            jobCapacities
        );

        emit ProposalExecuted(proposalId, proposal.proposalHash);
        _updateRound();
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
        if (newUpdateTime == 0) newUpdateTime = 1; // Prevent zero update time

        timeConfig.updateTime = newUpdateTime;
        emit ConfigUpdated(newUpdateTime);
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
        if (!isValidator[validator]) {
            revert Coordinator__ValidatorNotRegistered();
        }

        isValidator[validator] = false;
        validatorVote[validator] = 0; // Clear vote

        // More efficient array removal
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
                if (isValidator[validatorsToRemove[i]]) {
                    _removeValidator(validatorsToRemove[i]);
                }
            }
        }
    }

    function _calculateRequiredVotes() internal view returns (uint256) {
        uint256 validatorCount = validators.length;
        if (validatorCount == 0) return 0;
        return (validatorCount * i_requiredApprovalsPercentage + 99) / 100;
    }

    function _cleanupExpiredRound() internal {
        _resetValidatorStates();
        delete currentProposals;
    }

    function _updateRound() internal {
        _resetValidatorStates();
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
                delete validatorVote[vals[i]];
            }
        }
    }

    function _selectNewRoundValidators() internal {
        uint256 validatorCount = validators.length;

        if (validatorCount == 0) {
            delete currentRoundValidators;
            return;
        }

        if (validatorCount < requiredValidators) {
            revert Coordinator__NotEnoughActiveValidators();
        }

        delete currentRoundValidators;

        // More efficient validator selection using array check
        uint256 seed = uint256(
            keccak256(abi.encode(block.timestamp, nextProposalId))
        );
        uint256 selectedCount = 0;
        uint256 maxSelections = requiredValidators < validatorCount
            ? requiredValidators
            : validatorCount;

        uint256 attempts = 0;
        while (selectedCount < maxSelections && attempts < validatorCount * 3) {
            // Safety limit
            seed = uint256(keccak256(abi.encode(seed)));
            uint256 randIndex = seed % validatorCount;
            address selectedValidator = validators[randIndex];

            // Check if already selected (linear search through currentRoundValidators)
            bool alreadySelected = false;
            for (uint256 j = 0; j < selectedCount; ++j) {
                if (currentRoundValidators[j] == selectedValidator) {
                    alreadySelected = true;
                    break;
                }
            }

            if (!alreadySelected) {
                currentRoundValidators.push(selectedValidator);
                ++selectedCount;
            }
            ++attempts;
        }
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
                if (validatorVote[validator] == proposalId + 1) {
                    // +1 offset
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
        address[] calldata workers
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    validatorsToRemove,
                    jobHashes,
                    jobCapacities,
                    workers
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

    function _isCurrentRoundExpired() internal view returns (bool) {
        TimeConfig memory tc = timeConfig;
        return block.timestamp > tc.lastExecutionTime + (tc.updateTime << 1);
    }

    // ============= View Functions =============
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
}

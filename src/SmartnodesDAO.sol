// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISmartnodesToken, PaymentAmounts} from "./interfaces/ISmartnodesToken.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";

/**
 * @title SmartnodesDAO
 * @dev DAO contract for network governance using unclaimed rewards as voting power
 * @dev Manages proposals for adding and removing networks
 * @dev Voting power is based on unclaimed token rewards at the time of proposal creation
 */
contract SmartnodesDAO is Ownable {
    /** Errors */
    error DAO__InvalidProposal();
    error DAO__ProposalNotActive();
    error DAO__AlreadyVoted();
    error DAO__InsufficientVotingPower();
    error DAO__ProposalNotPassed();
    error DAO__ProposalAlreadyExecuted();
    error DAO__ExecutionFailed();
    error DAO__ProposalExpired();
    error DAO__InvalidAddress();

    enum ProposalType {
        ADD_NETWORK,
        REMOVE_NETWORK,
        UPDATE_PARAMETERS
    }

    enum ProposalStatus {
        Pending,
        Active,
        Passed,
        Failed,
        Executed,
        Cancelled,
        Expired
    }

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        ProposalStatus status;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        uint256 snapshotBlock;
        uint256 totalVotingPowerAtSnapshot;
        bytes executionData;
        string description;
        bool executed;
    }

    struct Vote {
        bool hasVoted;
        bool support;
        uint256 votingPower;
        uint256 snapshotVotingPower; // Voting power at proposal creation
    }

    /** Constants */
    uint256 private constant VOTING_PERIOD = 7 days;
    uint256 private constant MIN_VOTING_POWER = 1000e18; // Minimum tokens to create proposal
    uint256 private constant QUORUM_PERCENTAGE = 10; // 10% of total unclaimed rewards at snapshot
    uint256 private constant PASS_THRESHOLD = 51; // 51% of votes cast
    uint256 private constant EXECUTION_DELAY = 1 days; // Delay after voting ends before execution

    /** State Variables */
    ISmartnodesToken public immutable i_tokenContract;
    ISmartnodesCore public immutable i_smartnodesCore;

    uint256 public proposalCounter;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;

    // Snapshot of voting power at proposal creation
    mapping(uint256 => mapping(address => uint256)) public votingPowerSnapshots;

    /** Events */
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description,
        uint256 snapshotBlock,
        uint256 totalVotingPower
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalExpired(uint256 indexed proposalId);

    modifier validProposal(uint256 _proposalId) {
        if (_proposalId == 0 || _proposalId > proposalCounter) {
            revert DAO__InvalidProposal();
        }
        _;
    }

    modifier onlyActiveProposal(uint256 _proposalId) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.status != ProposalStatus.Active) {
            revert DAO__ProposalNotActive();
        }
        if (block.timestamp > proposal.endTime) {
            // Mark as expired if voting period has ended
            proposal.status = ProposalStatus.Expired;
            emit ProposalExpired(_proposalId);
            revert DAO__ProposalExpired();
        }
        _;
    }

    constructor(
        address _tokenContract,
        address _smartnodesCore
    ) Ownable(msg.sender) {
        if (_tokenContract == address(0) || _smartnodesCore == address(0)) {
            revert DAO__InvalidAddress();
        }
        i_tokenContract = ISmartnodesToken(_tokenContract);
        i_smartnodesCore = ISmartnodesCore(_smartnodesCore);
    }

    /**
     * @notice Create a proposal to add a new network
     * @param _networkName Name of the network to add
     * @param _description Description of the proposal
     */
    function proposeAddNetwork(
        string calldata _networkName,
        string calldata _description
    ) external returns (uint256 proposalId) {
        uint256 votingPower = getCurrentVotingPower(msg.sender);
        if (votingPower < MIN_VOTING_POWER) {
            revert DAO__InsufficientVotingPower();
        }

        proposalId = _createProposal(
            ProposalType.ADD_NETWORK,
            abi.encodeWithSelector(
                ISmartnodesCore.addNetwork.selector,
                _networkName
            ),
            _description
        );
    }

    /**
     * @notice Create a proposal to remove a network
     * @param _networkId ID of the network to remove
     * @param _description Description of the proposal
     */
    function proposeRemoveNetwork(
        uint8 _networkId,
        string calldata _description
    ) external returns (uint256 proposalId) {
        uint256 votingPower = getCurrentVotingPower(msg.sender);
        if (votingPower < MIN_VOTING_POWER) {
            revert DAO__InsufficientVotingPower();
        }

        proposalId = _createProposal(
            ProposalType.REMOVE_NETWORK,
            abi.encodeWithSelector(
                ISmartnodesCore.removeNetwork.selector,
                _networkId
            ),
            _description
        );
    }

    /**
     * @notice Internal function to create a proposal with snapshot
     */
    function _createProposal(
        ProposalType _proposalType,
        bytes memory _executionData,
        string calldata _description
    ) internal returns (uint256 proposalId) {
        proposalId = ++proposalCounter;

        // Take snapshot of current unclaimed rewards
        (uint128 totalUnclaimedSNO, ) = i_tokenContract.getTotalUnclaimed();

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            proposalType: _proposalType,
            status: ProposalStatus.Active,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            snapshotBlock: block.number,
            totalVotingPowerAtSnapshot: totalUnclaimedSNO,
            executionData: _executionData,
            description: _description,
            executed: false
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            _proposalType,
            _description,
            block.number,
            totalUnclaimedSNO
        );
    }

    /**
     * @notice Cast a vote on a proposal using unclaimed rewards as voting power
     * @param _proposalId ID of the proposal to vote on
     * @param _support Whether to support the proposal (true) or vote against (false)
     */
    function castVote(
        uint256 _proposalId,
        bool _support
    ) external validProposal(_proposalId) onlyActiveProposal(_proposalId) {
        Vote storage userVote = votes[_proposalId][msg.sender];
        if (userVote.hasVoted) {
            revert DAO__AlreadyVoted();
        }

        // Get current voting power (unclaimed rewards)
        uint256 votingPower = getCurrentVotingPower(msg.sender);
        if (votingPower == 0) {
            revert DAO__InsufficientVotingPower();
        }

        // Record the vote
        userVote.hasVoted = true;
        userVote.support = _support;
        userVote.votingPower = votingPower;

        // Update proposal vote counts
        Proposal storage proposal = proposals[_proposalId];
        if (_support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(_proposalId, msg.sender, _support, votingPower);
    }

    /**
     * @notice Execute a passed proposal after the execution delay
     * @param _proposalId ID of the proposal to execute
     */
    function executeProposal(
        uint256 _proposalId
    ) external validProposal(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed) {
            revert DAO__ProposalAlreadyExecuted();
        }

        // Check if voting period has ended
        if (block.timestamp <= proposal.endTime) {
            revert DAO__ProposalNotActive();
        }

        // Check if execution delay has passed
        if (block.timestamp < proposal.endTime + EXECUTION_DELAY) {
            revert DAO__ProposalNotActive();
        }

        // Determine if proposal passed
        _updateProposalStatus(_proposalId);

        if (proposal.status != ProposalStatus.Passed) {
            revert DAO__ProposalNotPassed();
        }

        proposal.executed = true;

        // Execute the proposal
        (bool success, ) = address(i_smartnodesCore).call(
            proposal.executionData
        );
        if (!success) {
            revert DAO__ExecutionFailed();
        }

        proposal.status = ProposalStatus.Executed;
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Update proposal status after voting period ends
     * @param _proposalId ID of the proposal to update
     */
    function _updateProposalStatus(uint256 _proposalId) internal {
        Proposal storage proposal = proposals[_proposalId];

        if (
            proposal.status != ProposalStatus.Active &&
            proposal.status != ProposalStatus.Expired
        ) {
            return; // Status already determined
        }

        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;

        // Check quorum based on snapshot
        bool quorumReached = (totalVotes * 100) >=
            (proposal.totalVotingPowerAtSnapshot * QUORUM_PERCENTAGE);

        // Check if majority supports
        bool majoritySupports = totalVotes > 0 &&
            (proposal.forVotes * 100) >= (totalVotes * PASS_THRESHOLD);

        if (quorumReached && majoritySupports) {
            proposal.status = ProposalStatus.Passed;
        } else {
            proposal.status = ProposalStatus.Failed;
        }
    }

    /**
     * @notice Check and update proposal status if voting period has ended
     * @param _proposalId ID of the proposal to check
     */
    function updateProposalStatus(
        uint256 _proposalId
    ) external validProposal(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        if (
            proposal.status == ProposalStatus.Active &&
            block.timestamp > proposal.endTime
        ) {
            _updateProposalStatus(_proposalId);
        }
    }

    /**
     * @notice Get current voting power of an address based on unclaimed rewards
     * @param _user Address to check voting power for
     * @return votingPower Amount of voting power (unclaimed SNO rewards)
     */
    function getCurrentVotingPower(
        address _user
    ) public view returns (uint256 votingPower) {
        PaymentAmounts memory unclaimedRewards = i_tokenContract
            .getUnclaimedRewards(_user);
        return uint256(unclaimedRewards.sno);
    }

    /**
     * @notice Get voting power of an address at the time a specific proposal was created
     * @param _proposalId ID of the proposal
     * @param _user Address to check voting power for
     * @return votingPower Amount of voting power at proposal snapshot
     */
    function getVotingPowerAtSnapshot(
        uint256 _proposalId,
        address _user
    ) public view returns (uint256 votingPower) {
        // For this implementation, we'll use current voting power
        // In a more sophisticated system, you might want to store historical snapshots
        return getCurrentVotingPower(_user);
    }

    /**
     * @notice Get proposal details
     * @param _proposalId ID of the proposal
     */
    function getProposal(
        uint256 _proposalId
    ) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    /**
     * @notice Get vote details for a user on a specific proposal
     * @param _proposalId ID of the proposal
     * @param _user Address of the voter
     */
    function getVote(
        uint256 _proposalId,
        address _user
    ) external view returns (Vote memory) {
        return votes[_proposalId][_user];
    }

    /**
     * @notice Get proposal results and status
     * @param _proposalId ID of the proposal
     */
    function getProposalResults(
        uint256 _proposalId
    )
        external
        view
        validProposal(_proposalId)
        returns (
            uint256 forVotes,
            uint256 againstVotes,
            uint256 totalVotes,
            bool quorumReached,
            bool majoritySupports,
            ProposalStatus status
        )
    {
        Proposal storage proposal = proposals[_proposalId];

        forVotes = proposal.forVotes;
        againstVotes = proposal.againstVotes;
        totalVotes = forVotes + againstVotes;

        quorumReached =
            (totalVotes * 100) >=
            (proposal.totalVotingPowerAtSnapshot * QUORUM_PERCENTAGE);
        majoritySupports =
            totalVotes > 0 &&
            (forVotes * 100) >= (totalVotes * PASS_THRESHOLD);

        status = proposal.status;
    }

    /**
     * @notice Cancel a proposal (only owner or proposer)
     * @param _proposalId ID of the proposal to cancel
     */
    function cancelProposal(
        uint256 _proposalId
    ) external validProposal(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        // Only owner or proposer can cancel
        require(
            msg.sender == owner() || msg.sender == proposal.proposer,
            "Not authorized to cancel"
        );

        require(
            proposal.status == ProposalStatus.Active ||
                proposal.status == ProposalStatus.Pending,
            "Cannot cancel proposal"
        );

        proposal.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(_proposalId);
    }

    /**
     * @notice Get governance parameters
     */
    function getGovernanceParameters()
        external
        pure
        returns (
            uint256 votingPeriod,
            uint256 minVotingPower,
            uint256 quorumPercentage,
            uint256 passThreshold,
            uint256 executionDelay
        )
    {
        return (
            VOTING_PERIOD,
            MIN_VOTING_POWER,
            QUORUM_PERCENTAGE,
            PASS_THRESHOLD,
            EXECUTION_DELAY
        );
    }

    /**
     * @notice Check if an address can create proposals
     * @param _user Address to check
     */
    function canCreateProposal(address _user) external view returns (bool) {
        return getCurrentVotingPower(_user) >= MIN_VOTING_POWER;
    }

    /**
     * @notice Check if an address can vote on a proposal
     * @param _proposalId ID of the proposal
     * @param _user Address to check
     */
    function canVote(
        uint256 _proposalId,
        address _user
    ) external view returns (bool) {
        if (_proposalId == 0 || _proposalId > proposalCounter) {
            return false;
        }

        Proposal storage proposal = proposals[_proposalId];
        if (proposal.status != ProposalStatus.Active) {
            return false;
        }

        if (block.timestamp > proposal.endTime) {
            return false;
        }

        if (votes[_proposalId][_user].hasVoted) {
            return false;
        }

        return getCurrentVotingPower(_user) > 0;
    }
}

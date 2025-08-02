// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISmartnodesToken, PaymentAmounts} from "./interfaces/ISmartnodesToken.sol";
import {ISmartnodesCore} from "./interfaces/ISmartnodesCore.sol";

/**
 * @title SmartnodesDAO
 * @dev DAO contract for network governance using unclaimed rewards as voting power
 * @dev Manages proposals for adding and removing networks
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

    enum ProposalType {
        ADD_NETWORK,
        REMOVE_NETWORK
    }

    enum ProposalStatus {
        Pending,
        Active,
        Passed,
        Failed,
        Executed,
        Cancelled
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
        bytes executionData;
        string description;
        bool executed;
    }

    struct Vote {
        bool hasVoted;
        bool support;
        uint256 votingPower;
    }

    /** Constants */
    uint256 private constant VOTING_PERIOD = 7 days;
    uint256 private constant MIN_VOTING_POWER = 1000e18; // Minimum tokens to create proposal
    uint256 private constant QUORUM_PERCENTAGE = 10; // 10% of total unclaimed rewards
    uint256 private constant PASS_THRESHOLD = 51; // 51% of votes cast

    /** State Variables */
    ISmartnodesToken public immutable i_tokenContract;
    ISmartnodesCore public immutable i_smartnodesCore;

    uint256 public proposalCounter;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;

    /** Events */
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);

    constructor(
        address _tokenContract,
        address _smartnodesCore
    ) Ownable(msg.sender) {
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
        uint256 votingPower = getVotingPower(msg.sender);
        if (votingPower < MIN_VOTING_POWER) {
            revert DAO__InsufficientVotingPower();
        }

        proposalId = ++proposalCounter;

        // Encode the addNetwork call
        bytes memory executionData = abi.encodeWithSelector(
            ISmartnodesCore.addNetwork.selector,
            _networkName
        );

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            proposalType: ProposalType.ADD_NETWORK,
            status: ProposalStatus.Active,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            executionData: executionData,
            description: _description,
            executed: false
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            ProposalType.ADD_NETWORK,
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
        uint256 votingPower = getVotingPower(msg.sender);
        if (votingPower < MIN_VOTING_POWER) {
            revert DAO__InsufficientVotingPower();
        }

        proposalId = ++proposalCounter;

        // Encode the removeNetwork call
        bytes memory executionData = abi.encodeWithSelector(
            ISmartnodesCore.removeNetwork.selector,
            _networkId
        );

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            proposalType: ProposalType.REMOVE_NETWORK,
            status: ProposalStatus.Active,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            executionData: executionData,
            description: _description,
            executed: false
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            ProposalType.REMOVE_NETWORK,
            _description
        );
    }

    /**
     * @notice Cast a vote on a proposal
     * @param _proposalId ID of the proposal to vote on
     * @param _support Whether to support the proposal (true) or vote against (false)
     */
    function castVote(uint256 _proposalId, bool _support) external {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.status != ProposalStatus.Active) {
            revert DAO__ProposalNotActive();
        }

        if (block.timestamp > proposal.endTime) {
            revert DAO__ProposalNotActive();
        }

        Vote storage userVote = votes[_proposalId][msg.sender];
        if (userVote.hasVoted) {
            revert DAO__AlreadyVoted();
        }

        uint256 votingPower = getVotingPower(msg.sender);
        if (votingPower == 0) {
            revert DAO__InsufficientVotingPower();
        }

        userVote.hasVoted = true;
        userVote.support = _support;
        userVote.votingPower = votingPower;

        if (_support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(_proposalId, msg.sender, _support, votingPower);
    }

    /**
     * @notice Execute a passed proposal
     * @param _proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed) {
            revert DAO__ProposalAlreadyExecuted();
        }

        if (block.timestamp <= proposal.endTime) {
            revert DAO__ProposalNotActive();
        }

        // Check if proposal passed
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
        (uint128 unclaimedSNO, uint128 unclaimedETH) = i_tokenContract
            .getTotalUnclaimed();

        // Check quorum
        bool quorumReached = (totalVotes * 100) >=
            (unclaimedSNO * QUORUM_PERCENTAGE);

        // Check if majority supports
        bool majoritySupports = (proposal.forVotes * 100) >=
            (totalVotes * PASS_THRESHOLD);

        if (!quorumReached || !majoritySupports) {
            proposal.status = ProposalStatus.Failed;
            revert DAO__ProposalNotPassed();
        }

        proposal.status = ProposalStatus.Passed;
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
     * @notice Get voting power of an address based on unclaimed rewards
     * @param _user Address to check voting power for
     * @return votingPower Amount of voting power (unclaimed rewards)
     */
    function getVotingPower(
        address _user
    ) public view returns (uint256 votingPower) {
        PaymentAmounts memory unclaimedRewards = i_tokenContract
            .getUnclaimedRewards(_user);
        return (uint256(unclaimedRewards.sno));
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
     * @notice Cancel a proposal (only owner)
     * @param _proposalId ID of the proposal to cancel
     */
    function cancelProposal(uint256 _proposalId) external onlyOwner {
        Proposal storage proposal = proposals[_proposalId];
        require(
            proposal.status == ProposalStatus.Active,
            "Proposal not active"
        );

        proposal.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(_proposalId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SmartnodesDAO is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant MAX_TARGETS = 3;
    uint256 public constant MIN_VOTING_PERIOD = 1 days;
    uint256 public constant MAX_VOTING_PERIOD = 30 days;
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MINIMUM_PROPOSAL_THRESHOLD = 1000e18;

    // Custom errors
    error SmartnodesDAO__ZeroAddress();
    error SmartnodesDAO__InvalidProposalId();
    error SmartnodesDAO__TooManyTargets();
    error SmartnodesDAO__InvalidVotingPeriod();
    error SmartnodesDAO__InsufficientProposalThreshold();
    error SmartnodesDAO__AlreadyVoted();
    error SmartnodesDAO__ProposalNotActive();
    error SmartnodesDAO__ProposalAlreadyExecuted();
    error SmartnodesDAO__ProposalNotQueued();
    error SmartnodesDAO__TimelockNotMet();
    error SmartnodesDAO__GracePeriodExpired();
    error SmartnodesDAO__ExecutionFailed(uint256 idx);
    error SmartnodesDAO__NoLockedTokens();
    error SmartnodesDAO__QuorumNotReached();
    error SmartnodesDAO__ProposalDidNotPass();
    error SmartnodesDAO__MismatchedArrays();
    error SmartnodesDAO__InsufficientTokens();
    error SmartnodesDAO__InvalidQuorumPercentage();
    error SmartnodesDAO__NotProposer();

    IERC20 public immutable token;

    uint256 public proposalCount;
    uint256 public votingPeriod;
    uint256 public quorumPercentage; // Basis points (e.g., 1000 = 10%)

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        uint128 id;
        uint128 startTime;
        uint128 endTime;
        uint128 queueTime;
        uint128 forVotes;
        uint128 againstVotes;
        address proposer;
        bool executed;
        bool canceled;
        bool queued;
        address[] targets;
        bytes[] calldatas;
        string description;
    }

    // Mappings
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => uint256)) public tokensLocked;
    mapping(address => uint256) public totalTokensLockedBy;

    // Events
    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        address[] targets,
        uint256 startTime,
        uint256 endTime,
        string description
    );

    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votes,
        uint256 tokensStaked
    );

    event ProposalQueued(uint256 indexed proposalId, uint256 executionTime);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    event RefundClaimed(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 amount
    );

    modifier validProposal(uint256 proposalId) {
        if (proposalId == 0 || proposalId > proposalCount) {
            revert SmartnodesDAO__InvalidProposalId();
        }
        _;
    }

    constructor(
        address _token,
        uint256 _votingPeriod,
        uint256 _quorumPercentage
    ) {
        if (_token == address(0)) revert SmartnodesDAO__ZeroAddress();
        if (
            _votingPeriod < MIN_VOTING_PERIOD ||
            _votingPeriod > MAX_VOTING_PERIOD
        ) {
            revert SmartnodesDAO__InvalidVotingPeriod();
        }
        if (_quorumPercentage == 0 || _quorumPercentage > 10000) {
            revert SmartnodesDAO__InvalidQuorumPercentage();
        }

        token = IERC20(_token);
        votingPeriod = _votingPeriod;
        quorumPercentage = _quorumPercentage;
    }

    // ---------- Proposal Functions ----------

    function propose(
        address[] calldata targets,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256) {
        uint256 targetsLength = targets.length;

        // Input validation
        if (targetsLength == 0 || targetsLength > MAX_TARGETS) {
            revert SmartnodesDAO__TooManyTargets();
        }
        if (calldatas.length != targetsLength) {
            revert SmartnodesDAO__MismatchedArrays();
        }
        if (token.balanceOf(msg.sender) < MINIMUM_PROPOSAL_THRESHOLD) {
            revert SmartnodesDAO__InsufficientProposalThreshold();
        }

        // Validate targets
        for (uint256 i = 0; i < targetsLength; ++i) {
            if (targets[i] == address(0)) revert SmartnodesDAO__ZeroAddress();
        }

        unchecked {
            ++proposalCount;
        }
        uint256 id = proposalCount;

        Proposal storage p = proposals[id];
        p.id = uint128(id);
        p.proposer = msg.sender;
        p.startTime = uint128(block.timestamp);
        p.endTime = uint128(block.timestamp + votingPeriod);

        // Copy arrays
        p.targets = new address[](targetsLength);
        p.calldatas = new bytes[](targetsLength);
        for (uint256 i = 0; i < targetsLength; ++i) {
            p.targets[i] = targets[i];
            p.calldatas[i] = calldatas[i];
        }
        p.description = description;

        emit ProposalCreated(
            id,
            msg.sender,
            p.targets,
            p.startTime,
            p.endTime,
            description
        );

        return id;
    }

    /**
     * @dev Vote on a proposal with 1:1 token voting power
     * @param proposalId The proposal to vote on
     * @param support Whether to vote for (true) or against (false)
     * @param tokensToLock The amount of tokens to lock for this vote
     */
    function vote(
        uint256 proposalId,
        bool support,
        uint256 tokensToLock
    ) external nonReentrant validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];

        if (block.timestamp < p.startTime || block.timestamp >= p.endTime) {
            revert SmartnodesDAO__ProposalNotActive();
        }
        if (hasVoted[proposalId][msg.sender]) {
            revert SmartnodesDAO__AlreadyVoted();
        }
        if (tokensToLock == 0) {
            revert SmartnodesDAO__InsufficientTokens();
        }

        // Transfer tokens (will revert if insufficient balance/approval)
        token.safeTransferFrom(msg.sender, address(this), tokensToLock);

        // Update state
        hasVoted[proposalId][msg.sender] = true;
        tokensLocked[proposalId][msg.sender] = tokensToLock;
        totalTokensLockedBy[msg.sender] += tokensToLock;

        // Convert to vote count (1:1 token to vote ratio)
        uint256 votes = tokensToLock;

        if (support) {
            p.forVotes += uint128(votes);
        } else {
            p.againstVotes += uint128(votes);
        }

        emit Voted(proposalId, msg.sender, support, votes, tokensToLock);
    }

    function queue(
        uint256 proposalId
    ) external nonReentrant validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];
        ProposalState currentState = state(proposalId);

        if (currentState != ProposalState.Succeeded) {
            revert SmartnodesDAO__ProposalDidNotPass();
        }

        p.queued = true;
        p.queueTime = uint128(block.timestamp + TIMELOCK_DELAY);

        emit ProposalQueued(proposalId, p.queueTime);
    }

    function execute(
        uint256 proposalId
    ) external nonReentrant validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];
        ProposalState currentState = state(proposalId);

        if (currentState != ProposalState.Queued) {
            revert SmartnodesDAO__ProposalNotQueued();
        }
        if (block.timestamp < p.queueTime) {
            revert SmartnodesDAO__TimelockNotMet();
        }
        if (block.timestamp > p.queueTime + GRACE_PERIOD) {
            revert SmartnodesDAO__GracePeriodExpired();
        }

        p.executed = true;

        // Execute all calls
        uint256 targetsLength = p.targets.length;
        for (uint256 i = 0; i < targetsLength; ++i) {
            (bool success, bytes memory returnData) = p.targets[i].call(
                p.calldatas[i]
            );
            if (!success) {
                // Handle revert reason
                if (returnData.length > 0) {
                    assembly {
                        revert(add(32, returnData), mload(returnData))
                    }
                } else {
                    revert SmartnodesDAO__ExecutionFailed(i);
                }
            }
        }

        emit ProposalExecuted(proposalId);
    }

    function cancel(uint256 proposalId) external validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];

        // Only proposer can cancel their own proposal
        if (msg.sender != p.proposer) {
            revert SmartnodesDAO__NotProposer();
        }

        ProposalState currentState = state(proposalId);
        if (currentState == ProposalState.Executed) {
            revert SmartnodesDAO__ProposalAlreadyExecuted();
        }

        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    // ---------- Refund Functions ----------

    function claimRefund(
        uint256 proposalId
    ) external nonReentrant validProposal(proposalId) {
        ProposalState currentState = state(proposalId);

        // Can only claim after proposal is no longer active
        if (
            currentState == ProposalState.Active ||
            currentState == ProposalState.Pending
        ) {
            revert SmartnodesDAO__ProposalNotActive();
        }

        uint256 locked = tokensLocked[proposalId][msg.sender];
        if (locked == 0) revert SmartnodesDAO__NoLockedTokens();

        // Clear state before transfer
        tokensLocked[proposalId][msg.sender] = 0;

        // Update total safely
        uint256 currentTotal = totalTokensLockedBy[msg.sender];
        totalTokensLockedBy[msg.sender] = currentTotal >= locked
            ? currentTotal - locked
            : 0;

        token.safeTransfer(msg.sender, locked);
        emit RefundClaimed(proposalId, msg.sender, locked);
    }

    function batchClaimRefunds(
        uint256[] calldata proposalIds
    ) external nonReentrant {
        uint256 totalRefund = 0;
        uint256 proposalIdsLength = proposalIds.length;

        for (uint256 i = 0; i < proposalIdsLength; ++i) {
            uint256 proposalId = proposalIds[i];
            if (proposalId == 0 || proposalId > proposalCount) continue;

            ProposalState currentState = state(proposalId);
            if (
                currentState == ProposalState.Active ||
                currentState == ProposalState.Pending
            ) {
                continue;
            }

            uint256 locked = tokensLocked[proposalId][msg.sender];
            if (locked > 0) {
                tokensLocked[proposalId][msg.sender] = 0;
                totalRefund += locked;
                emit RefundClaimed(proposalId, msg.sender, locked);
            }
        }

        if (totalRefund > 0) {
            // Update total safely
            uint256 currentTotal = totalTokensLockedBy[msg.sender];
            totalTokensLockedBy[msg.sender] = currentTotal >= totalRefund
                ? currentTotal - totalRefund
                : 0;

            token.safeTransfer(msg.sender, totalRefund);
        }
    }

    // ---------- View Functions ----------

    function state(uint256 proposalId) public view returns (ProposalState) {
        if (proposalId == 0 || proposalId > proposalCount) {
            revert SmartnodesDAO__InvalidProposalId();
        }

        Proposal storage p = proposals[proposalId];

        if (p.canceled) {
            return ProposalState.Canceled;
        }
        if (p.executed) {
            return ProposalState.Executed;
        }
        if (block.timestamp < p.startTime) {
            return ProposalState.Pending;
        }
        if (block.timestamp < p.endTime) {
            return ProposalState.Active;
        }

        // Proposal ended, check results
        uint256 requiredQuorum = quorumRequired();
        uint256 totalVotes = uint256(p.forVotes) + uint256(p.againstVotes);

        if (totalVotes < requiredQuorum || p.forVotes <= p.againstVotes) {
            return ProposalState.Defeated;
        }

        if (p.queued) {
            if (block.timestamp >= p.queueTime + GRACE_PERIOD) {
                return ProposalState.Expired;
            }
            return ProposalState.Queued;
        }

        return ProposalState.Succeeded;
    }

    function getProposal(
        uint256 proposalId
    ) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getVotesOf(
        uint256 proposalId,
        address voter
    ) external view returns (bool voted, uint256 lockedTokens) {
        voted = hasVoted[proposalId][voter];
        lockedTokens = tokensLocked[proposalId][voter];
    }

    function getProposalVotes(
        uint256 proposalId
    )
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 totalVotes)
    {
        Proposal storage p = proposals[proposalId];
        forVotes = p.forVotes;
        againstVotes = p.againstVotes;
        totalVotes = forVotes + againstVotes;
    }

    function quorumRequired() public view returns (uint256) {
        uint256 totalSupply = token.totalSupply();
        return (totalSupply * quorumPercentage) / 10000;
    }

    receive() external payable {
        // Accept ETH deposits for execution costs
    }
}

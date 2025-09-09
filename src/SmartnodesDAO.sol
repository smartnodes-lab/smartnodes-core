// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/*
  SmartnodesDAO

  - Quadratic voting: voter supplies `n` votes and must stake `n * n` tokens.
  - Supports proposals that contain up to 3 targets (addresses) and arbitrary calldata per target.
  - Votes are counted as `n` (not n^2); tokens staked = n^2 and are locked in DAO until refund.
  - Simple quorum and voting window; admin (deployer) can update parameters.
  - Uses SafeERC20 & ReentrancyGuard.
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract SmartnodesDAO is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    error SmartnodesDAO__ZeroAddress();
    error SmartnodesDAO__TooManyTargets();
    error SmartnodesDAO__InvalidVotingPeriod();
    error SmartnodesDAO__NotEnoughStake();
    error SmartnodesDAO__AlreadyVoted();
    error SmartnodesDAO__ProposalNotActive();
    error SmartnodesDAO__ProposalAlreadyExecuted();
    error SmartnodesDAO__NotProposerOrAdmin();
    error SmartnodesDAO__ExecutionFailed(uint256 idx);
    error SmartnodesDAO__AlreadyClaimed();
    error SmartnodesDAO__NoLockedTokens();

    IERC20 public immutable token; // your SNO token
    address public admin;

    uint256 public proposalCount;
    uint256 public votingPeriod; // seconds

    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets; // up to 3
        bytes[] calldatas; // same length as targets
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes; // sum of votes (n)
        uint256 againstVotes; // sum of votes (n)
        bool executed;
        bool canceled;
    }

    // proposalId => Proposal
    mapping(uint256 => Proposal) public proposals;

    // proposalId => voter => votesCast (n)
    mapping(uint256 => mapping(address => uint256)) public votesCast;

    // proposalId => voter => tokensLocked (n*n)
    mapping(uint256 => mapping(address => uint256)) public tokensLocked;

    // voter => total tokens locked across proposals (helper)
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
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event RefundClaimed(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 amount
    );
    event VotingParamsUpdated(uint256 votingPeriod, uint256 quorumVotes);
    event AdminTransferred(address oldAdmin, address newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "SmartnodesDAO: only admin");
        _;
    }

    constructor(address _token, uint256 _votingPeriod) {
        if (_token == address(0)) revert SmartnodesDAO__ZeroAddress();
        if (_votingPeriod == 0) revert SmartnodesDAO__InvalidVotingPeriod();

        token = IERC20(_token);
        admin = msg.sender;
        votingPeriod = _votingPeriod;
    }

    // ---------- Admin / Config ----------
    function transferAdmin(address _new) external onlyAdmin {
        if (_new == address(0)) revert SmartnodesDAO__ZeroAddress();
        address old = admin;
        admin = _new;
        emit AdminTransferred(old, _new);
    }

    // ---------- Proposal lifecycle ----------
    /// @notice Create a proposal with 1..3 targets and associated calldata.
    function propose(
        address[] calldata targets,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256) {
        uint256 tlen = targets.length;
        if (tlen == 0 || tlen > 3) revert SmartnodesDAO__TooManyTargets();
        if (calldatas.length != tlen) revert("mismatched arrays");

        proposalCount++;
        uint256 id = proposalCount;

        Proposal storage p = proposals[id];
        p.id = id;
        p.proposer = msg.sender;

        // copy arrays
        p.targets = new address[](tlen);
        p.calldatas = new bytes[](tlen);
        for (uint256 i = 0; i < tlen; ++i) {
            if (targets[i] == address(0)) revert SmartnodesDAO__ZeroAddress();
            p.targets[i] = targets[i];
            p.calldatas[i] = calldatas[i];
        }

        p.description = description;
        p.startTime = block.timestamp;
        p.endTime = block.timestamp + votingPeriod;
        p.executed = false;
        p.canceled = false;

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

    /// @notice Quadratic voting: voter chooses `n` votes. Required token stake = n * n.
    /// Voter must approve DAO for at least `n*n` tokens prior to calling.
    function vote(
        uint256 proposalId,
        uint256 nVotes,
        bool support
    ) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        if (p.id == 0) revert("proposal not found");
        if (block.timestamp < p.startTime || block.timestamp >= p.endTime)
            revert SmartnodesDAO__ProposalNotActive();
        if (nVotes == 0) revert("votes must be > 0");
        if (votesCast[proposalId][msg.sender] != 0)
            revert SmartnodesDAO__AlreadyVoted(); // one vote per voter per proposal in this simple design

        // cost = nVotes * nVotes
        uint256 cost = nVotes * nVotes;

        // transfer tokens in from voter to DAO (staking)
        token.safeTransferFrom(msg.sender, address(this), cost);

        // record
        votesCast[proposalId][msg.sender] = nVotes;
        tokensLocked[proposalId][msg.sender] = cost;
        totalTokensLockedBy[msg.sender] += cost;

        if (support) {
            p.forVotes += nVotes;
        } else {
            p.againstVotes += nVotes;
        }

        emit Voted(proposalId, msg.sender, support, nVotes, cost);
    }

    /// @notice After voting period ends, anybody can call execute when passed.
    function execute(uint256 proposalId) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        if (p.id == 0) revert("proposal not found");
        if (block.timestamp < p.endTime)
            revert SmartnodesDAO__ProposalNotActive();
        if (p.executed) revert SmartnodesDAO__ProposalAlreadyExecuted();
        if (p.canceled) revert("proposal canceled");

        uint256 quorumVotes = token.totalSupply() / 5; // must have at least 20% of existing holders votes

        // pass conditions: forVotes > againstVotes && quorum reached
        if (p.forVotes <= p.againstVotes) revert("proposal did not pass");
        if (p.forVotes < quorumVotes) revert("quorum not reached");

        // execute stored calls (revert if any call fails)
        uint256 len = p.targets.length;
        for (uint256 i = 0; i < len; ++i) {
            (bool ok, bytes memory returndata) = p.targets[i].call{value: 0}(
                p.calldatas[i]
            );
            if (!ok) {
                // bubble up revert reason if present
                revert SmartnodesDAO__ExecutionFailed(i);
            }
        }

        p.executed = true;
        emit ProposalExecuted(proposalId);
    }

    /// @notice Proposer or admin can cancel an active proposal (refunds still claimable)
    function cancel(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.id == 0) revert("proposal not found");
        if (msg.sender != p.proposer && msg.sender != admin)
            revert SmartnodesDAO__NotProposerOrAdmin();
        if (p.executed) revert SmartnodesDAO__ProposalAlreadyExecuted();
        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    // ---------- Refunds ----------
    /// @notice After the voting ends (or after execution/cancel), voter can reclaim their staked tokens.
    function claimRefund(uint256 proposalId) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        if (p.id == 0) revert("proposal not found");
        if (block.timestamp < p.endTime && !p.executed && !p.canceled)
            revert("voting still active");

        uint256 locked = tokensLocked[proposalId][msg.sender];
        if (locked == 0) revert SmartnodesDAO__NoLockedTokens();

        // zero out before transfer
        tokensLocked[proposalId][msg.sender] = 0;
        uint256 ref = totalTokensLockedBy[msg.sender];

        // reduce totalTokensLockedBy safely
        if (ref >= locked) {
            ref -= locked;
        } else {
            ref = 0;
        }

        token.safeTransfer(msg.sender, locked);
        emit RefundClaimed(proposalId, msg.sender, locked);
    }

    // ---------- Views ----------
    function getProposal(
        uint256 proposalId
    ) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getVotesOf(
        uint256 proposalId,
        address voter
    ) external view returns (uint256 votes, uint256 lockedTokens) {
        votes = votesCast[proposalId][voter];
        lockedTokens = tokensLocked[proposalId][voter];
    }

    receive() external payable {}
}

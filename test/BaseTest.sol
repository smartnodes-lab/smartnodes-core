// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {SmartnodesERC20} from "../src/SmartnodesERC20.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";

/**
 * @title BaseSmartnodesTest
 * @notice Base test contract with common setup for all Smartnodes tests
 */
abstract contract BaseSmartnodesTest is Test {
    uint256 constant DEPLOYMENT_MULTIPLIER = 1;
    uint128 constant INTERVAL_SECONDS = 1 minutes;
    uint256 constant VALIDATOR_REWARD_PERCENTAGE = 10;
    uint256 constant DAO_REWARD_PERCENTAGE = 3;
    uint256 constant ADDITIONAL_SNO_PAYMENT = 1000e18;
    uint256 constant ADDITIONAL_ETH_PAYMENT = 5 ether;
    uint256 constant INITIAL_EMISSION_RATE = 5832e18;
    uint256 constant TAIL_EMISSION = 420e18;
    uint256 constant VALIDATOR_LOCK_AMOUNT = 1_000_000e18;
    uint256 constant USER_LOCK_AMOUNT = 100e18;
    uint256 constant UNLOCK_PERIOD = 14 days;
    uint256 constant REWARD_PERIOD = 365 days;
    uint256 constant DAO_VOTING_PERIOD = 7 days;

    // Test participants structure
    struct Participant {
        address addr;
        uint256 capacity;
        bool isValidator;
    }

    // Contract instances
    SmartnodesERC20 public token;
    SmartnodesCore public core;
    SmartnodesCoordinator public coordinator;
    SmartnodesDAO public dao;

    // Test addresses
    address public deployerAddr = makeAddr("deployer");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");
    address public worker1 = makeAddr("worker1");
    address public worker2 = makeAddr("worker2");
    address public worker3 = makeAddr("worker3");
    address[] public genesisNodes;
    address[] public activeNodes;

    // Test constants
    bytes32 constant USER1_PUBKEY = keccak256("user1_pubkey");
    bytes32 constant USER2_PUBKEY = keccak256("user2_pubkey");
    bytes32 constant VALIDATOR1_PUBKEY = keccak256("validator1_pubkey");
    bytes32 constant VALIDATOR2_PUBKEY = keccak256("validator2_pubkey");
    bytes32 constant VALIDATOR3_PUBKEY = keccak256("validator3_pubkey");
    bytes32 constant JOB_ID_1 = keccak256("job1");
    bytes32 constant JOB_ID_2 = keccak256("job2");

    function setUp() public virtual {
        _deployContracts();
        _setupInitialState();
    }

    function _deployContracts() internal {
        vm.startPrank(deployerAddr);

        // Setup genesis nodes
        genesisNodes.push(validator1);
        genesisNodes.push(validator2);
        genesisNodes.push(validator3);
        genesisNodes.push(user1);
        genesisNodes.push(user2);
        // genesisNodes.push(worker1);
        // genesisNodes.push(worker2);
        // genesisNodes.push(worker3);

        token = new SmartnodesERC20(DEPLOYMENT_MULTIPLIER, genesisNodes);
        dao = new SmartnodesDAO(address(token), DAO_VOTING_PERIOD, 500);
        core = new SmartnodesCore(address(token));

        // Deploy coordinator
        coordinator = new SmartnodesCoordinator(
            INTERVAL_SECONDS,
            66,
            address(core),
            address(token),
            activeNodes
        );

        // Set DAO in token (can only be done once)
        token.setSmartnodes(address(core), address(coordinator));

        token.setDAO(address(dao));
        core.setCoordinator(address(coordinator));

        vm.stopPrank();
    }

    function _setupInitialState() internal virtual {
        // Ensure validators have enough tokens and ETH
        vm.deal(validator1, 10 ether);
        vm.deal(validator2, 10 ether);
        vm.deal(validator3, 10 ether);
        vm.deal(worker1, 5 ether);
        vm.deal(worker2, 5 ether);
        vm.deal(worker3, 5 ether);

        _setupTestParticipants(10000, true);

        vm.prank(validator1);
        core.createValidator(VALIDATOR1_PUBKEY);
        vm.prank(validator1);
        coordinator.addValidator();
    }

    // Helper function for tests that need to create DAO proposals
    function createDAOProposal(
        address[] memory targets,
        bytes[] memory calldatas,
        uint256[] memory values,
        string memory description
    ) internal returns (uint256 proposalId) {
        proposalId = dao.propose(targets, calldatas, values, description);
    }

    // Helper function to vote on DAO proposals in tests
    function voteOnProposal(
        uint256 proposalId,
        address voter,
        uint256 votes,
        bool support
    ) internal {
        vm.startPrank(voter);
        token.approve(address(dao), votes);
        dao.vote(proposalId, support, votes);
        vm.stopPrank();
    }

    // Helper function to execute DAO proposals in tests
    function executeProposal(uint256 proposalId) internal {
        vm.warp(block.timestamp + DAO_VOTING_PERIOD + 1);
        dao.queue(proposalId);
        vm.warp(block.timestamp + dao.TIMELOCK_DELAY());
        dao.execute(proposalId);
    }

    // ============= Helper Functions =============
    function createTestUser(address user, bytes32 pubkey) internal {
        vm.prank(user);
        core.createUser(pubkey);
    }

    function fundUserWithETH(address user, uint256 amount) internal {
        vm.deal(user, amount);
    }

    function createTestJob(
        address user,
        bytes32 jobId,
        uint256[] memory capacities,
        uint256 ethPayment
    ) internal {
        vm.prank(user);
        if (ethPayment > 0) {
            core.requestJob{value: ethPayment}(
                user == user1 ? USER1_PUBKEY : USER2_PUBKEY,
                jobId,
                "tensorlink",
                capacities,
                0
            );
        } else {
            core.requestJob(
                user == user1 ? USER1_PUBKEY : USER2_PUBKEY,
                jobId,
                "tensorlink",
                capacities,
                1000e18
            );
        }
    }

    function createBasicProposal(address validator) internal returns (uint8) {
        // Helper to create a basic proposal for testing
        bytes32[] memory jobHashes = new bytes32[](1);
        jobHashes[0] = JOB_ID_1;

        address[] memory jobWorkers = new address[](1);
        jobWorkers[0] = worker1;

        uint256[] memory jobCapacities = new uint256[](1);
        jobCapacities[0] = 100;

        address[] memory validatorsToRemove = new address[](0);
        (
            Participant[] memory participants,
            uint256 totalCapacity
        ) = _setupTestParticipants(jobWorkers.length, false);
        bytes32[] memory leaves = _generateLeaves(participants);
        bytes32 merkleRoot = _buildMerkleTree(leaves);

        bytes32 proposalHash = keccak256(
            abi.encode(
                merkleRoot,
                validatorsToRemove,
                JOB_ID_1,
                JOB_ID_1,
                JOB_ID_1,
                block.timestamp
            )
        );

        vm.prank(validator);
        coordinator.createProposal(proposalHash);

        uint8 proposalId = coordinator.getNumProposals();
        return proposalId;
    }

    /**
     * @notice Generate Merkle tree leaves from participants
     */
    function _generateLeaves(
        Participant[] memory participants
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](participants.length);

        for (uint256 i = 0; i < participants.length; i++) {
            leaves[i] = keccak256(
                abi.encode(participants[i].addr, participants[i].capacity)
            );
        }

        return leaves;
    }

    /**
     * @notice Generate Merkle proof for a specific leaf index
     */
    function _generateMerkleProof(
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (bytes32[] memory) {
        if (leaves.length <= 1) return new bytes32[](0);
        if (index >= leaves.length) revert("Index out of bounds");

        bytes32[] memory proof = new bytes32[](32);
        uint256 proofLength = 0;

        bytes32[] memory currentLevel = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            currentLevel[i] = leaves[i];
        }

        uint256 currentIndex = index;

        while (currentLevel.length > 1) {
            uint256 siblingIndex;
            if (currentIndex % 2 == 0) {
                siblingIndex = currentIndex + 1;
            } else {
                siblingIndex = currentIndex - 1;
            }

            if (siblingIndex < currentLevel.length) {
                proof[proofLength] = currentLevel[siblingIndex];
            } else {
                proof[proofLength] = currentLevel[currentIndex];
            }
            proofLength++;

            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLevelSize);

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                bytes32 left = currentLevel[i];
                bytes32 right = (i + 1 < currentLevel.length)
                    ? currentLevel[i + 1]
                    : currentLevel[i];

                bytes32 combinedHash;
                if (left <= right) {
                    combinedHash = keccak256(abi.encodePacked(left, right));
                } else {
                    combinedHash = keccak256(abi.encodePacked(right, left));
                }

                nextLevel[i / 2] = combinedHash;
            }

            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
        }

        bytes32[] memory trimmedProof = new bytes32[](proofLength);
        for (uint256 i = 0; i < proofLength; i++) {
            trimmedProof[i] = proof[i];
        }

        return trimmedProof;
    }

    /**
     * @notice Build Merkle tree root from leaves
     */
    function _buildMerkleTree(
        bytes32[] memory leaves
    ) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];

        bytes32[] memory currentLevel = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            currentLevel[i] = leaves[i];
        }

        while (currentLevel.length > 1) {
            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLevelSize);

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                bytes32 left = currentLevel[i];
                bytes32 right = (i + 1 < currentLevel.length)
                    ? currentLevel[i + 1]
                    : currentLevel[i];

                if (left <= right) {
                    nextLevel[i / 2] = keccak256(abi.encodePacked(left, right));
                } else {
                    nextLevel[i / 2] = keccak256(abi.encodePacked(right, left));
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    // Helper to find participant index (no sorting)
    function _findParticipantIndex(
        Participant[] memory participants,
        address target
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].addr == target) {
                return i;
            }
        }
        revert("Participant not found");
    }

    // Helper to get capacity for an address
    function _getCapacityForAddress(
        Participant[] memory participants,
        address addr
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].addr == addr) {
                return participants[i].capacity;
            }
        }
        revert("Address not found");
    }

    /**
     * @notice Setup participants for testing
     * @return participants Array of test participants
     * @return totalCapacity Total capacity of all participants
     */
    function _setupTestParticipants(
        uint256 numWorkers,
        bool deal
    )
        internal
        returns (Participant[] memory participants, uint256 totalCapacity)
    {
        require(numWorkers >= 0, "numWorkers must be >= 0");

        participants = new Participant[](numWorkers);
        totalCapacity = 0;

        for (uint256 i = 0; i < numWorkers; i++) {
            address workerAddr = address(uint160(0x3000 + i));
            uint256 capacity = 10 + (i * 5);

            participants[i] = Participant({
                addr: workerAddr,
                capacity: capacity,
                isValidator: false
            });
            totalCapacity += capacity;

            if (deal) {
                // Fund workers for testing
                vm.deal(workerAddr, 1 ether);
            }
        }

        console.log("Added workers with total capacity:", totalCapacity);
        console.log("Total system capacity:", totalCapacity);
    }

    /**
     * @notice Setup contract with additional funding
     */
    function _setupContractFunding() internal {
        vm.deal(address(core), ADDITIONAL_ETH_PAYMENT);
        vm.prank(address(core));
        (bool success, ) = address(token).call{value: ADDITIONAL_ETH_PAYMENT}(
            ""
        );
        require(success, "Funding failed");
    }

    /**
     * @notice Validate final system state
     */
    function _validateFinalState() internal view {
        (uint128 unclaimedSno, uint128 unclaimedEth) = token.s_totalUnclaimed();

        console.log("Remaining unclaimed SNO:", unclaimedSno / 1e18);
        console.log("Remaining unclaimed ETH:", unclaimedEth / 1e18);

        // Should be zero or very close to zero (accounting for rounding)
        assertLt(unclaimedSno, 1e15, "Too much SNO left unclaimed"); // Less than 0.001 SNO
        assertLt(unclaimedEth, 1e15, "Too much ETH left unclaimed"); // Less than 0.001 ETH
    }
}

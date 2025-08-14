// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {SmartnodesCoordinator} from "../src/SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "../src/SmartnodesDAO.sol";

/**
 * @title BaseSmartnodesTest
 * @notice Base test contract with common setup for all Smartnodes tests
 */
abstract contract BaseSmartnodesTest is Test {
    // Contract instances
    SmartnodesToken public token;
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

    // Test constants
    bytes32 constant USER1_PUBKEY = keccak256("user1_pubkey");
    bytes32 constant USER2_PUBKEY = keccak256("user2_pubkey");
    bytes32 constant VALIDATOR1_PUBKEY = keccak256("validator1_pubkey");
    bytes32 constant VALIDATOR2_PUBKEY = keccak256("validator2_pubkey");
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
        genesisNodes.push(user1);
        genesisNodes.push(user2);

        token = new SmartnodesToken(genesisNodes);
        core = new SmartnodesCore(address(token));
        coordinator = new SmartnodesCoordinator(
            3600,
            66,
            address(core),
            genesisNodes
        );
        dao = new SmartnodesDAO(address(token), address(core));

        token.setSmartnodesCore(address(core));
        core.setCoordinator(address(coordinator));

        token.transferOwnership(msg.sender);
        dao.transferOwnership(msg.sender);

        vm.stopPrank();
    }

    function _setupInitialState() internal virtual {
        // createTestValidator(validator1, VALIDATOR1_PUBKEY);
        // createTestValidator(validator2, VALIDATOR2_PUBKEY);
        // vm.prank(validator2);
        // core.createValidator(VALIDATOR2_PUBKEY);
    }

    // ============= Helper Functions =============

    function addTestNetwork(
        string memory networkName
    ) internal returns (uint8) {
        vm.prank(deployerAddr);
        core.addNetwork(networkName);
        return core.networkCounter();
    }

    function createTestValidator(address validator, bytes32 pubkey) internal {
        vm.prank(validator);
        core.createValidator(pubkey);
        coordinator.addValidator(validator);
    }

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
        uint8 networkId,
        uint256[] memory capacities,
        uint256 ethPayment
    ) internal {
        vm.prank(user);
        if (ethPayment > 0) {
            core.requestJob{value: ethPayment}(
                user == user1 ? USER1_PUBKEY : USER2_PUBKEY,
                jobId,
                networkId,
                capacities,
                0
            );
        } else {
            core.requestJob(
                user == user1 ? USER1_PUBKEY : USER2_PUBKEY,
                jobId,
                networkId,
                capacities,
                1000e18 // Default SNO payment
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

        bytes32 proposalHash = keccak256(
            abi.encode(
                validatorsToRemove,
                jobHashes,
                jobCapacities,
                jobWorkers,
                block.timestamp
            )
        );

        vm.prank(validator);
        coordinator.createProposal(proposalHash);

        uint8 proposalId = coordinator.getNumProposals();
        return proposalId;
    }

    function executeProposalRound() internal {
        bytes32[] memory jobHashes = new bytes32[](1);
        address[] memory jobWorkers = new address[](1);
        uint256[] memory jobCapacities = new uint256[](1);
        address[] memory validatorsToRemove = new address[](0);
        jobHashes[0] = JOB_ID_1;
        jobWorkers[0] = worker1;
        jobCapacities[0] = 100;

        createTestValidator(validator1, bytes32("a"));

        vm.startPrank(validator1);
        vm.warp(block.timestamp + 60 * 60 * 2);

        bytes32 proposalHash = keccak256(
            abi.encode(
                validatorsToRemove,
                jobHashes,
                jobCapacities,
                jobWorkers,
                block.timestamp
            )
        );

        coordinator.createProposal(proposalHash);
        coordinator.voteForProposal(1);
        coordinator.executeProposal(
            1,
            validatorsToRemove,
            jobHashes,
            jobWorkers,
            jobCapacities
        );
        vm.stopPrank();
    }
}

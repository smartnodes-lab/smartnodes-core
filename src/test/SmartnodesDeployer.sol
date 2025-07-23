// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {SmartnodesToken} from "../SmartnodesToken.sol";
import {SmartnodesCore} from "../SmartnodesCore.sol";

/**
 * @title SmartnodesDeployer
 * @dev Contract for deploying and configuring Smartnodes ecosystem
 * @dev Ensures proper initialization order and configuration
 */
contract SmartnodesDeployer {
    event SmartnodesEcosystemDeployed(
        address indexed tokenContract,
        address indexed coreContract,
        address[] genesisNodes,
        uint256 timestamp
    );

    event DeploymentFailed(string reason);

    struct DeploymentConfig {
        address[] genesisNodes;
        string tokenName;
        string tokenSymbol;
    }

    /**
     * @dev Deploys the complete Smartnodes ecosystem
     * @param _genesisNodes Array of genesis node addresses to receive initial tokens
     * @return tokenAddress Address of deployed SmartnodesToken contract
     * @return coreAddress Address of deployed SmartnodesCore contract
     */
    function deploySmartnodesEcosystem(
        address[] memory _genesisNodes
    ) public returns (address tokenAddress, address coreAddress) {
        // Validate genesis nodes
        require(
            _genesisNodes.length > 0,
            "Must have at least one genesis node"
        );
        require(_genesisNodes.length <= 10, "Too many genesis nodes");

        // Validate addresses
        for (uint256 i = 0; i < _genesisNodes.length; i++) {
            require(
                _genesisNodes[i] != address(0),
                "Invalid genesis node address"
            );

            // Check for duplicates
            for (uint256 j = i + 1; j < _genesisNodes.length; j++) {
                require(
                    _genesisNodes[i] != _genesisNodes[j],
                    "Duplicate genesis node"
                );
            }
        }

        try this._deployContracts(_genesisNodes) returns (
            address token,
            address core
        ) {
            tokenAddress = token;
            coreAddress = core;

            emit SmartnodesEcosystemDeployed(
                tokenAddress,
                coreAddress,
                _genesisNodes,
                block.timestamp
            );
        } catch Error(string memory reason) {
            emit DeploymentFailed(reason);
            revert(reason);
        } catch {
            emit DeploymentFailed("Unknown deployment error");
            revert("Deployment failed");
        }
    }

    /**
     * @dev Internal function to handle the actual deployment
     * @param _genesisNodes Array of genesis node addresses
     * @return tokenAddress Address of deployed token contract
     * @return coreAddress Address of deployed core contract
     */
    function _deployContracts(
        address[] memory _genesisNodes
    ) external returns (address tokenAddress, address coreAddress) {
        require(msg.sender == address(this), "Internal function only");

        // Step 1: Deploy SmartnodesToken first
        SmartnodesToken token = new SmartnodesToken(_genesisNodes);
        tokenAddress = address(token);

        // Step 2: Deploy SmartnodesCore with token address
        SmartnodesCore core = new SmartnodesCore(tokenAddress);
        coreAddress = address(core);

        // Step 3: Set the core contract in token (critical for proper functioning)
        token.setSmartnodesCore(coreAddress);

        // Step 4: Transfer token ownership to deployer (msg.sender of original call)
        token.transferOwnership(tx.origin);
    }

    /**
     * @dev Helper function to estimate gas for deployment
     * @param _genesisNodes Array of genesis node addresses
     * @return estimatedGas Estimated gas needed for deployment
     */
    function estimateDeploymentGas(
        address[] memory _genesisNodes
    ) external view returns (uint256 estimatedGas) {
        // Base gas for contract creation and setup
        uint256 baseGas = 3_000_000; // ~3M gas base

        // Additional gas per genesis node (for minting)
        uint256 gasPerNode = 50_000; // ~50k gas per node

        estimatedGas = baseGas + (_genesisNodes.length * gasPerNode);
    }

    /**
     * @dev Batch deployment with configuration validation
     * @param configs Array of deployment configurations
     * @return deployments Array of deployed contract addresses
     */
    function batchDeploy(
        DeploymentConfig[] memory configs
    ) external returns (address[2][] memory deployments) {
        require(configs.length > 0, "No configurations provided");
        require(configs.length <= 5, "Too many batch deployments");

        deployments = new address[2][](configs.length);

        for (uint256 i = 0; i < configs.length; i++) {
            (address token, address core) = deploySmartnodesEcosystem(
                configs[i].genesisNodes
            );
            deployments[i][0] = token;
            deployments[i][1] = core;
        }
    }
}

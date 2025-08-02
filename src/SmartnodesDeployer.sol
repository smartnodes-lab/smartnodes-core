// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {SmartnodesToken} from "./SmartnodesToken.sol";
import {SmartnodesCore} from "./SmartnodesCore.sol";
import {SmartnodesCoordinator} from "./SmartnodesCoordinator.sol";
import {SmartnodesDAO} from "./SmartnodesDAO.sol";

/**
 * @title SmartnodesDeployer
 * @dev Contract for deploying and configuring complete Smartnodes ecosystem including DAO
 * @dev Ensures proper initialization order and configuration
 */
contract SmartnodesDeployer {
    event SmartnodesEcosystemDeployed(
        address indexed tokenContract,
        address indexed coreContract,
        address indexed coordinatorContract,
        address daoContract,
        address[] genesisNodes,
        uint256 timestamp
    );

    event DeploymentFailed(string reason);

    struct DeploymentConfig {
        address[] genesisNodes;
        string tokenName;
        string tokenSymbol;
        bool deployDAO;
    }

    /**
     * @dev Deploys the complete Smartnodes ecosystem with optional DAO
     * @param _genesisNodes Array of genesis node addresses to receive initial tokens
     * @return tokenAddress Address of deployed token contract
     * @return coreAddress Address of deployed core contract
     * @return coordinatorAddress Address of deployed coordinator contract
     * @return daoAddress Address of deployed DAO contract
     */
    function deploySmartnodesEcosystem(
        address[] memory _genesisNodes
    )
        public
        returns (
            address tokenAddress,
            address coreAddress,
            address coordinatorAddress,
            address daoAddress
        )
    {
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

        (
            tokenAddress,
            coreAddress,
            coordinatorAddress,
            daoAddress
        ) = _deployContracts(_genesisNodes);

        emit SmartnodesEcosystemDeployed(
            tokenAddress,
            coreAddress,
            coordinatorAddress,
            daoAddress,
            _genesisNodes,
            block.timestamp
        );
    }

    /**
     * @dev Internal function to handle the actual deployment
     * @param _genesisNodes Array of genesis node addresses
     * @return tokenAddress Address of deployed token contract
     * @return coreAddress Address of deployed core contract
     * @return coordinatorAddress Address of deployed coordinator contract
     * @return daoAddress Address of deployed DAO contract (address(0) if not deployed)
     */
    function _deployContracts(
        address[] memory _genesisNodes
    )
        internal
        returns (
            address tokenAddress,
            address coreAddress,
            address coordinatorAddress,
            address daoAddress
        )
    {
        // Step 1: Deploy SmartnodesToken first
        SmartnodesToken token = new SmartnodesToken(_genesisNodes);
        tokenAddress = address(token);

        // Step 2: Deploy SmartnodesCore with token address
        SmartnodesCore core = new SmartnodesCore(tokenAddress);
        coreAddress = address(core);

        // Step 3: Deploy SmartnodesCoordinator with core address
        SmartnodesCoordinator coordinator = new SmartnodesCoordinator(
            uint128(3600), // Update time (1 hour)
            uint8(66), // Approvals percentage
            coreAddress,
            _genesisNodes
        );
        coordinatorAddress = address(coordinator);

        // Step 4: Deploy DAO
        SmartnodesDAO dao = new SmartnodesDAO(tokenAddress, coreAddress);
        daoAddress = address(dao);

        // Step 5: Set the core contract in token (critical for proper functioning)
        token.setSmartnodesCore(coreAddress);
        core.setCoordinator(coordinatorAddress);

        // Step 6: Transfer ownership to deployer (msg.sender of original call)
        // Note: Consider transferring DAO ownership to a multisig or governance timelock
        token.transferOwnership(msg.sender);
        SmartnodesDAO(daoAddress).transferOwnership(msg.sender);
    }

    /**
     * @dev Helper function to estimate gas for deployment
     * @param _genesisNodes Array of genesis node addresses
     * @param _deployDAO Whether DAO will be deployed
     * @return estimatedGas Estimated gas needed for deployment
     */
    function estimateDeploymentGas(
        address[] memory _genesisNodes,
        bool _deployDAO
    ) external pure returns (uint256 estimatedGas) {
        // Base gas for contract creation and setup
        uint256 baseGas = 3_500_000; // ~3.5M gas base (increased for DAO)

        // Additional gas per genesis node (for minting)
        uint256 gasPerNode = 50_000; // ~50k gas per node

        // Additional gas for DAO deployment
        uint256 daoGas = _deployDAO ? 1_500_000 : 0; // ~1.5M gas for DAO

        estimatedGas = baseGas + (_genesisNodes.length * gasPerNode) + daoGas;
    }

    /**
     * @dev Verify deployment integrity
     * @return isValid Whether the deployment is properly configured
     */
    function verifyDeployment(
        address token,
        address core,
        address coordinator,
        address dao
    ) external view returns (bool isValid) {
        try this._verifyIntegrity(token, core, coordinator, dao) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @dev Internal verification of deployment integrity
     */
    function _verifyIntegrity(
        address _token,
        address _core,
        address _coordinator,
        address _dao
    ) external view {
        require(msg.sender == address(this), "Internal function only");

        // Verify token contract
        SmartnodesToken token = SmartnodesToken(_token);
        require(
            address(token.getSmartnodesCore()) == _core,
            "Token-Core link invalid"
        );

        // Verify core contract
        SmartnodesCore core = SmartnodesCore(_core);
        require(
            address(core.getCoordinator()) == _coordinator,
            "Core-Coordinator link invalid"
        );

        // Verify DAO if deployed
        if (_dao != address(0)) {
            SmartnodesDAO dao = SmartnodesDAO(_dao);
            require(
                address(dao.i_tokenContract()) == _token,
                "DAO-Token link invalid"
            );
            require(
                address(dao.i_smartnodesCore()) == _core,
                "DAO-Core link invalid"
            );
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct PaymentAmounts {
    uint128 sno;
    uint128 eth;
}

/**
 * @title ISmartnodesToken Interface
 * @dev Interface for the SmartnodesToken contract
 */
interface ISmartnodesToken {
    function setValidatorLockAmount(uint256 _newAmount) external;

    function setUserLockAmount(uint256 _newAmount) external;

    function lockTokens(address _validator, bool _isValidator) external;

    function unlockTokens(address _validator, bool _isValidator) external;

    function escrowPayment(address _user, uint256 _payment) external;

    function escrowEthPayment(address _user, uint256 _payment) external payable;

    function releaseEscrowedPayment(address _user, uint256 _amount) external;

    function releaseEscrowedEthPayment(address _user, uint256 _amount) external;

    function createMerkleDistribution(
        bytes32 _merkleRoot,
        uint256 _totalCapacity,
        address[] memory _approvedValidators,
        PaymentAmounts calldata _payments,
        address _biasValidator
    ) external;

    function claimMerkleRewards(
        uint256 _distributionId,
        uint256 _capacity,
        bytes32[] calldata _merkleProof
    ) external;

    function getEmissionRate() external view returns (uint256);

    function getTotalUnclaimed() external view returns (uint128, uint128);

    function setSmartnodes(
        address _smartnodesCore,
        address _smartnodesCoordinator
    ) external;
}

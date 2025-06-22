// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISmartnodesToken
 * @dev Interface for SmartnodesToken contract
 */
interface ISmartnodesToken {
    function escrowPayment(
        address _user,
        uint256 _amount,
        uint8 _networkId
    ) external;

    function releaseEscrow(address _user, uint256 _amount) external;

    function mintRewards(
        address[] calldata _workers,
        address[] calldata _validatorsVoted,
        uint256[] calldata _workerCapacities,
        uint256 additionalReward
    ) external;

    function createValidatorLock(address _validator) external;

    function unlockValidatorTokens(address _validator) external;

    function addNetwork(string calldata name) external;

    function getUnclaimedRewards(address user) external view returns (uint256);

    function isValidatorStaked(address validator) external view returns (bool);

    function getLockAmount() external view returns (uint256);
}

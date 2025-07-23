// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISmartnodesToken
 * @dev Interface for SmartnodesToken contract
 */
interface ISmartnodesToken {
    function lockTokens(address _validator) external;

    function unlockTokens(address _validator) external;

    function addNetwork(string calldata name) external;

    function getUnclaimedRewards(address user) external view returns (uint256);

    function getLockAmount() external view returns (uint256);

    function mintRewards(
        address[] calldata _workers,
        address[] calldata _validatorsVoted,
        uint256[] calldata _workerCapacities,
        uint256 additionalReward
    ) external;

    function escrowPayment(
        address _user,
        uint256 _payment,
        uint8 _networkId
    ) external returns (uint256);
}

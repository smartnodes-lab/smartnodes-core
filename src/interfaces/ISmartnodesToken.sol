// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISmartnodesToken Interface
 * @dev Interface for the SmartnodesToken contract
 */
interface ISmartnodesToken {
    function lockTokens(address _validator, uint8 _userType) external;

    function unlockTokens(address _validator, uint8 _userType) external;

    function escrowPayment(
        address _user,
        uint256 _payment,
        uint8 _networkId
    ) external;

    function escrowEthPayment(
        address _user,
        uint256 _payment,
        uint8 _networkId
    ) external payable;

    function releaseEscrowedPayment(address _user, uint256 _amount) external;

    function releaseEscrowedEthPayment(address _user, uint256 _amount) external;

    function mintRewards(
        address[] calldata _validators,
        address[] calldata _workers,
        uint256[] calldata _capacities,
        uint256 _additionalReward,
        uint256 _additionalEthReward
    ) external;

    function getEmissionRate() external view returns (uint256);

    function getUnclaimedTokenRewards(
        address _user
    ) external view returns (uint256);

    function getUnclaimedEthRewards(
        address _user
    ) external view returns (uint256);
}

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
    function lockTokens(address _validator, bool _isValidator) external;

    function unlockTokens(address _validator, bool _isValidator) external;

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
        PaymentAmounts calldata _payments
    ) external;

    function getEmissionRate() external view returns (uint256);

    function getUnclaimedTokenRewards(
        address _user
    ) external view returns (uint256);

    function getUnclaimedEthRewards(
        address _user
    ) external view returns (uint256);
}

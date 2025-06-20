// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISmartnodesToken {
    // ========== Errors ==========
    error SmartnodesToken__InvalidCaller();
    error SmartnodesToken__InvalidWorkerData();

    // ========== External Functions ==========

    /**
     * @notice Distribute rewards to workers and validators
     * @dev Callable only by SmartnodesCore
     */
    function mintRewards(
        address[] calldata _workers,
        address[] calldata _validatorsVoted,
        uint256[] calldata _workerCapacities,
        uint256 additionalReward
    ) external;

    /**
     * @notice Claim any accumulated unclaimed rewards
     */
    function claimRewards() external;

    /**
     * @notice Called to update the emission rate based on the era
     * @dev Callable only by SmartnodesCore
     */
    function updateEmissionRate() external;

    /**
     * @notice Get the current emission rate based on the emission schedule
     * @return emissionRate Current emission rate
     */
    function getEmissionRate() external view returns (uint256 emissionRate);
}

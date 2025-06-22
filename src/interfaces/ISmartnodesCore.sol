// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISmartnodesCore
 * @dev Interface for SmartnodesCore contract
 */
interface ISmartnodesCore {
    function validatorExists(
        address validatorAddress
    ) external view returns (bool);

    function addNetwork(string calldata name) external;

    function getValidatorInfo(
        address validatorAddress
    ) external view returns (bytes32, bool);

    function getJobInfo(
        bytes32 jobId
    ) external view returns (uint128, address, uint8, bool);
}

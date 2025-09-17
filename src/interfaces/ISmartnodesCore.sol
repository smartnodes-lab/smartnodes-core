// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ISmartnodesCoordinator} from "./ISmartnodesCoordinator.sol";

/**
 * @title ISmartnodesCore Interface
 * @dev Interface for the SmartnodesCore contract
 */
interface ISmartnodesCore {
    enum JobState {
        DoesntExist,
        Pending,
        Active,
        Complete
    }

    enum PaymentType {
        SNO_TOKEN,
        ETH
    }

    struct Job {
        uint128 payment;
        uint8 networkId;
        uint8 state;
        uint8 paymentType;
        address owner;
    }

    function addNetwork(string calldata _name) external;

    function removeNetwork(uint8 _networkId) external;

    function createValidator(bytes32 publicKeyHash) external;

    function createUser(bytes32 publicKeyHash) external;

    function requestJob(
        bytes32 _userId,
        bytes32 _jobId,
        uint8 _networkId,
        uint256[] calldata _capacities,
        uint128 _payment
    ) external payable;

    function updateContract(
        bytes32[] calldata _jobIds,
        bytes32 _merkleRoot,
        uint256 _totalCapacity,
        address[] memory _approvedValidators,
        address _biasValidator
    ) external;

    function jobs(
        bytes32 _jobId
    )
        external
        view
        returns (
            uint128 payment,
            uint8 networkId,
            uint8 state,
            uint8 paymentType,
            address owner
        );

    function isLockedValidator(address validator) external view returns (bool);

    function getCoordinator() external view returns (ISmartnodesCoordinator);
}

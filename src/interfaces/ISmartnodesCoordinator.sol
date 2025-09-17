// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ISmartnodesCoordinator {
    function updateTiming(uint256 _newInterval) external;
}

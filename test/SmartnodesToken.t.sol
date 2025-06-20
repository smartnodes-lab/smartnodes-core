// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SmartnodesToken} from "../src/SmartnodesToken.sol";
import {Test} from "forge-std/Test.sol";

contract SmartnodesTokenTest is Test {
    SmartnodesToken private smartnodesToken;

    // Test constructor to initialize the contract with genesis nodes and core address
    function setUp() public {
        address[2] gensisNodes;
        gensisNodes[0] = address(0x123);
        gensisNodes[1] = address(0x456);
        smartnodesCore = address(0x789);

        smartnodesToken = new SmartnodesToken(gensisNodes, smartnodesCore);
    }

    // Function to test the mintRewards functionality
    function testMintRewards(
        address[] memory _workers,
        address[] memory _validators,
        uint256[] memory _validatorsVoted,
        uint256 additionalReward
    ) public {
        vm.assume(_workers.length < 100);
        vm.assume(_validators.length < 10);
        vm.assume(_validatorsVoted.length < 10);

        smartnodesToken.mintRewards(
            _workers,
            _validators,
            _validatorsVoted,
            additionalReward
        );
    }
}

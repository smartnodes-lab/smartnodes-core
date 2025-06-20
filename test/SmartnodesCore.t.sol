// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SmartnodesCore} from "../src/SmartnodesCore.sol";
import {DeploySmartnodes} from "../script/Deploy.s.sol";

contract SmartnodesCoreTest is Test {
    SmartnodesCore private smartnodesCore;

    function setUp() public {
        DeploySmartnodes deploySmartnodes = new DeploySmartnodes();
        smartnodesCore = deploySmartnodes.run();
    }

    function testInitialEmissionRate() public {
        assertEq(smartnodesCore.emissionRate(), 4096e18);
    }

    function testInitialTotalUnclaimedRewards() public {
        assertEq(smartnodesCore.totalUnclaimedRewards(), 0);
    }
}

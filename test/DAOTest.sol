// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.22;

// import {console} from "forge-std/Test.sol";
// import {SmartnodesToken} from "../src/SmartnodesToken.sol";
// import {BaseSmartnodesTest} from "./BaseTest.sol";

// /**
//  * @title SmartnodesTokenTest
//  * @notice Comprehensive tests for SmartnodesToken contract functionality
//  */
// contract SmartnodesTokenTest is BaseSmartnodesTest {
//     function _setupInitialState() internal override {
//         // Token-specific setup
//         BaseSmartnodesTest._setupInitialState();
//         createTestUser(user1, USER1_PUBKEY);
//     }

//     /// @notice Full proposal lifecycle: propose -> vote -> execute -> refunds
//     function testDAOProposalLifecycleAndRefunds() public {
//         // Build calldata to call receiver.doSomething()
//         address;
//         targets[0] = address(receiver);

//         bytes;
//         calldatas[0] = abi.encodeWithSignature("doSomething()");

//         // create proposal as deployer
//         uint256 proposalId;
//         vm.prank(deployerAddr);
//         proposalId = dao.propose(
//             targets,
//             calldatas,
//             "Call receiver.doSomething"
//         );

//         // Validator1 casts an initial large vote (n = 50)
//         voteOnProposal(proposalId, validator1, 50, true);

//         // Add more votes from other genesis nodes to reach quorum (uses helper)
//         _addMoreVotesToProposal(proposalId);

//         // Advance time past voting period and execute
//         executeProposal(proposalId);

//         // Check receiver got called
//         bool executed = receiver.executed();
//         assertTrue(executed, "Receiver was not executed by DAO");

//         // Now ensure voters can claim refunds
//         // For example, validator1 should have staked 50*50 tokens (2500)
//         // Save pre-claim balance
//         uint256 preBal = token.balanceOf(validator1);

//         // Claim refund for validator1
//         vm.prank(validator1);
//         dao.claimRefund(proposalId);

//         uint256 postBal = token.balanceOf(validator1);
//         assertTrue(
//             postBal > preBal,
//             "Validator1 did not receive refunded tokens"
//         );

//         // Also check one of the other voters (validator2) can claim
//         uint256 pre2 = token.balanceOf(validator2);
//         vm.prank(validator2);
//         dao.claimRefund(proposalId);
//         uint256 post2 = token.balanceOf(validator2);
//         assertTrue(post2 > pre2, "Validator2 did not receive refunded tokens");
//     }
// }

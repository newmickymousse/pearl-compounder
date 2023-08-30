// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_setMinRewardsToSell() public {
        uint256 minRewardsToSell = 123e17;

        // user cannot change maxGasForMatching
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setMinRewardsToSell(minRewardsToSell);

        // management can change maxGasForMatching
        vm.prank(management);
        strategy.setMinRewardsToSell(minRewardsToSell);
        assertEq(strategy.minRewardsToSell(), minRewardsToSell);
    }
}

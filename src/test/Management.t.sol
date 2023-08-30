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

        // user cannot change minRewardsToSell
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setMinRewardsToSell(minRewardsToSell);

        // management can change minRewardsToSell
        vm.prank(management);
        strategy.setMinRewardsToSell(minRewardsToSell);
        assertEq(strategy.minRewardsToSell(), minRewardsToSell);
    }

    function test_setSlippage() public {
        uint256 slippage = 1000;

        // user cannot change minRewardsToSell
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setSlippage(slippage);

        // management can change minRewardsToSell
        vm.prank(management);
        strategy.setSlippage(slippage);
        assertEq(strategy.slippage(), slippage);

        // cannot change slippage above fee dominator
        vm.prank(management);
        vm.expectRevert("!slippage");
        strategy.setSlippage(10001);
    }
}

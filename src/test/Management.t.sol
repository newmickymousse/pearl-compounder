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

        // user cannot change slippage
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setSlippage(slippage);

        // management can change slippage
        vm.prank(management);
        strategy.setSlippage(slippage);
        assertEq(strategy.slippage(), slippage);

        // cannot change slippage above fee dominator
        vm.prank(management);
        vm.expectRevert("!slippage");
        strategy.setSlippage(10001);
    }

    function test_setSlippageStable() public {
        uint256 slippageStable = 20;

        // user cannot change slippageStable
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setSlippageStable(slippageStable);

        // management can change slippageStable
        vm.prank(management);
        strategy.setSlippageStable(slippageStable);
        assertEq(strategy.slippageStable(), slippageStable);

        // cannot change slippageStable above fee dominator
        vm.prank(management);
        vm.expectRevert("!slippageStable");
        strategy.setSlippageStable(10001);
    }
}

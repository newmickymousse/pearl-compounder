// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

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

    function test_calimFees() public {
        uint256 minRewardsToSell = 123e17;

        // user cannot claimFees
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.claimFees();

        // management can  claimFees
        vm.prank(management);
        strategy.claimFees();
    }

    function test_claimAndSellRewards() public {
        // user cannot claimAndSellRewards
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.claimAndSellRewards();

        // management can claimAndSellRewards
        vm.prank(management);
        strategy.claimAndSellRewards();
    }

    function test_sweep() public {
        uint256 amount = 1e18;
        ERC20 airdropedToken = new ERC20("AIR", "AR");
        deal(address(airdropedToken), address(strategy), amount);

        // user cannot sweep
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.sweep(address(airdropedToken));

        // management can sweep
        assertEq(airdropedToken.balanceOf(address(strategy)), amount);
        vm.prank(management);
        strategy.sweep(address(airdropedToken));
        assertEq(airdropedToken.balanceOf(address(strategy)), 0);
        assertEq(airdropedToken.balanceOf(management), amount);

        // management cannot sweep asset
        vm.prank(management);
        vm.expectRevert("!asset");
        strategy.sweep(address(asset));
    }
}

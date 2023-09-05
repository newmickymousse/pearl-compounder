// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_rewards() public {
        uint256 _amount = maxFuzzAmount;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(20 days);
        vm.roll(block.number + 1);

        uint256 claimableRewards = strategy.getClaimableRewards();
        assertGt(claimableRewards, 0, "!claimableRewards"); // tested with exchange values
        // console.log("claimableRewards", claimableRewards);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        claimableRewards = strategy.getClaimableRewards();
        assertEq(claimableRewards, 0, "!claimableRewards=0");

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
    }

    function test_rewardsWontClaim() public {
        uint256 _amount = maxFuzzAmount;

        vm.prank(management);
        strategy.setMinRewardsToSell(type(uint256).max);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(20 days);
        vm.roll(block.number + 1);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // there are pedning rewards
        uint256 claimableRewards = strategy.getClaimableRewards();
        assertGt(claimableRewards, 0, "!claimableRewards");

        // didn't claim any rewards

        uint256 pearlBalance = ERC20(tokenAddrs["PEARL"]).balanceOf(
            address(strategy)
        );
        assertEq(pearlBalance, 0, "!pearlBalance");

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
    }
}

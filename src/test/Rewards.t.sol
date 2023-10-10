// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IPair} from "../interfaces/PearlFi/IPair.sol";
import {IPearlRouter} from "../interfaces/PearlFi/IPearlRouter.sol";

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
        strategy.setMinRewardsToSell(type(uint256).max - 1);

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

    function test_rewardsAboveMaxToSell() public {
        uint256 _amount = maxFuzzAmount;

        vm.prank(management);
        strategy.setMaxRewardsToSell(1e20);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // airdpop rewards
        uint256 rewardsAbove = 1e20;
        deal(
            tokenAddrs["PEARL"],
            address(strategy),
            strategy.maxRewardsToSell() + rewardsAbove
        );

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // rewardsAbove should be in the strategy
        uint256 pearlBalance = ERC20(tokenAddrs["PEARL"]).balanceOf(
            address(strategy)
        );
        assertEq(pearlBalance, rewardsAbove, "!pearlBalance");
        uint256 balanceOfRewards = strategy.balanceOfRewards();
        assertEq(balanceOfRewards, pearlBalance, "!balanceOfRewards");
    }

    function test_cannotEarnLpFees() public {
        uint256 _amount = maxFuzzAmount / 10;

        vm.prank(management);
        strategy.setMaxRewardsToSell(1e20);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // assert strategy doesnt have LP token, asset token
        assertEq(
            ERC20(strategy.asset()).balanceOf(address(strategy)),
            0,
            "!LPbalance"
        );

        IPair pair = IPair(strategy.asset());
        ERC20 airdropToken;
        ERC20 otherToken;
        bool stable = pair.stable();

        // usdr token cannot be airdropped
        if (pair.token0() == tokenAddrs["USDR"]) {
            airdropToken = ERC20(pair.token1());
            otherToken = ERC20(pair.token0());
        } else {
            airdropToken = ERC20(pair.token0());
            otherToken = ERC20(pair.token1());
        }

        // airdpop usdc to user
        uint256 token0Amount;
        if (
            address(airdropToken) == tokenAddrs["WETH"] ||
            address(airdropToken) == tokenAddrs["WBTC"]
        ) {
            // these tokens have much higher value than stables
            token0Amount = 1 * 10 ** airdropToken.decimals();
        } else {
            token0Amount = 1000 * 10 ** airdropToken.decimals();
        }
        airdrop(airdropToken, address(user), token0Amount);

        IPearlRouter pearlRouter = IPearlRouter(
            0xcC25C0FD84737F44a7d38649b69491BBf0c7f083
        );
        // user approves usdc for router
        vm.prank(user);
        airdropToken.approve(address(pearlRouter), token0Amount);

        // user swaps usdc for usdr
        vm.prank(user);
        pearlRouter.swapExactTokensForTokensSimple(
            token0Amount,
            0,
            address(airdropToken),
            address(otherToken),
            stable, // stable
            address(strategy),
            block.timestamp
        );

        skip(2 days);
        vm.roll(block.number + 1);

        // verify there are LP fees even we have completed some swaps
        uint256 lpFees = strategy.getClaimableFeesValue();
        assertEq(lpFees, 0, "!lpFees");

        // Deposit into strategy to trigger LP token transfer from startegy address
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // assert there are no LP fees even we have completed some swaps and transfered LP token
        lpFees = strategy.getClaimableFeesValue();
        assertEq(lpFees, 0, "!lpFees");
    }
}

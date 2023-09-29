// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        console.log(_amount);
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

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

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

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(20 days);
        vm.roll(block.number + 1);

        // Report profit
        (bool shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertTrue(shouldReport);
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_reportTrigger() public {
        (bool shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertFalse(shouldReport);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, minFuzzAmount);

        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertFalse(shouldReport);

        // verify reportTrigger for idle rewards
        uint256 minRewardsToSell = strategy.minRewardsToSell();
        deal(tokenAddrs["PEARL"], address(strategy), minRewardsToSell + 1);
        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertTrue(shouldReport, "!shouldReportRewards");
        vm.prank(keeper);
        strategy.report();
        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertFalse(shouldReport, "!dontReport");

        // verify reportTrigger for pending rewards
        vm.prank(management);
        strategy.setMinRewardsToSell(1);
        skip(strategy.profitMaxUnlockTime() - 1 minutes);
        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertTrue(shouldReport, "!shouldReportPendingRewards");
        vm.prank(keeper);
        strategy.report();
        // set minRewardsToSell back to original value
        vm.prank(management);
        strategy.setMinRewardsToSell(minRewardsToSell);
        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertFalse(shouldReport, "!dontReport");

        // verify reportTrigger for time from last report
        skip(strategy.profitMaxUnlockTime() + 1 minutes);
        vm.roll(block.number + 1);
        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertTrue(shouldReport, "!shouldReportTime");
        vm.prank(keeper);
        strategy.report();
        (shouldReport, ) = strategy.reportTrigger(address(strategy));
        assertFalse(shouldReport, "!dontReport");
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        assertTrue(!strategy.tendTrigger());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertTrue(!strategy.tendTrigger());

        // Skip some time
        skip(1 days);

        assertTrue(!strategy.tendTrigger());

        vm.prank(keeper);
        strategy.report();

        assertTrue(!strategy.tendTrigger());

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        assertTrue(!strategy.tendTrigger());

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertTrue(!strategy.tendTrigger());
    }

    function test_airdropTokens(uint256 _amount, uint64 _airdrop) public {
        if (address(asset) != tokenAddrs["USDC-USDR-lp"]) {
            // change values
            return;
        }

        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 1e3);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // airdrop lp token, change token if needed
        _airdrop = uint64(bound(_airdrop, 100, 1e8));
        deal(tokenAddrs["USDC"], address(strategy), _airdrop);

        // airdrop pearl token
        deal(
            tokenAddrs["PEARL"],
            address(strategy),
            bound(_amount, minFuzzAmount, 1e22)
        );

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // all pearl is swapped to usdr
        uint256 minPearlToSell = strategy.minRewardsToSell();
        assertLe(
            ERC20(tokenAddrs["PEARL"]).balanceOf(address(strategy)),
            minPearlToSell,
            "PEARL !=0"
        );
        uint256 usdcBalance = ERC20(tokenAddrs["USDC"]).balanceOf(
            address(strategy)
        );

        // airdrop pearl token
        deal(tokenAddrs["PEARL"], address(strategy), usdcBalance * 1e12);
        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // more usdc is swapped and added to liquidity
        assertLe(
            ERC20(tokenAddrs["USDC"]).balanceOf(address(strategy)),
            usdcBalance,
            "USDC balance 2"
        );
    }

    function test_equalTokenSwap(uint256 _amount, uint64 _airdrop) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // swap in equal amounts, more usdr will be left
        vm.prank(management);
        strategy.setSwapTokenDiff(10_000);

        // airdrop pearl token
        deal(
            tokenAddrs["PEARL"],
            address(strategy),
            bound(_amount, minFuzzAmount, 1e22)
        );

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // all pearl is swapped to usdr
        uint256 minPearlToSell = strategy.minRewardsToSell();
        assertLe(
            ERC20(tokenAddrs["PEARL"]).balanceOf(address(strategy)),
            minPearlToSell,
            "PEARL !=0"
        );
        assertEq(
            ERC20(tokenAddrs["USDC"]).balanceOf(address(strategy)),
            0,
            "USDC !=0"
        );

        // some usdr is left
        assertGe(
            ERC20(tokenAddrs["USDR"]).balanceOf(address(strategy)),
            0,
            "USDR == 0"
        );
    }

    function test_lessTokenSwap(uint256 _amount, uint64 _airdrop) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // swap less for token, more left in usdr
        vm.prank(management);
        strategy.setSwapTokenDiff(9_000);

        // airdrop pearl token
        deal(
            tokenAddrs["PEARL"],
            address(strategy),
            bound(_amount, minFuzzAmount, 1e22)
        );

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // all pearl is swapped to usdr
        uint256 minPearlToSell = strategy.minRewardsToSell();
        assertLe(
            ERC20(tokenAddrs["PEARL"]).balanceOf(address(strategy)),
            minPearlToSell,
            "PEARL !=0"
        );
        assertEq(
            ERC20(tokenAddrs["USDC"]).balanceOf(address(strategy)),
            0,
            "USDC !=0"
        );

        //
        assertGe(
            ERC20(tokenAddrs["USDR"]).balanceOf(address(strategy)),
            0,
            "USDR == 0"
        );
    }

    function test_moreTokenSwap(uint256 _amount, uint64 _airdrop) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // swap more for token, less left in usdr
        vm.prank(management);
        strategy.setSwapTokenDiff(11_000);

        // airdrop pearl token
        deal(
            tokenAddrs["PEARL"],
            address(strategy),
            bound(_amount, minFuzzAmount, 1e22)
        );

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // all pearl is swapped to usdr
        uint256 minPearlToSell = strategy.minRewardsToSell();
        assertLe(
            ERC20(tokenAddrs["PEARL"]).balanceOf(address(strategy)),
            minPearlToSell,
            "PEARL !=0"
        );
        // all usdr is added to liquidity
        assertEq(
            ERC20(tokenAddrs["USDR"]).balanceOf(address(strategy)),
            0,
            "USDR !=0"
        );

        // usdc is left
        assertGe(
            ERC20(tokenAddrs["USDC"]).balanceOf(address(strategy)),
            0,
            "USDC == 0"
        );
    }

    function test_depositZero() public {
        mintAndDepositIntoStrategy(strategy, user, 1e18);
        vm.prank(user);
        strategy.redeem(1e10, user, user);
        vm.prank(user);
        vm.expectRevert("ZERO_SHARES");
        strategy.deposit(0, user);
    }

    function test_withdrawZero() public {
        mintAndDepositIntoStrategy(strategy, user, 1e18);
        vm.prank(user);
        vm.expectRevert("ZERO_ASSETS");
        strategy.redeem(0, user, user);
    }
}

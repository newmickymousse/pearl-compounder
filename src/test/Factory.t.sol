// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FactoryTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyFactoryOK() public {
        console.log("address of strategy factory", address(strategyFactory));
        assertTrue(address(0) != address(strategyFactory));
        assertEq(strategyFactory.management(), management);
        assertEq(
            strategyFactory.performanceFeeRecipient(),
            performanceFeeRecipient
        );
        assertEq(strategyFactory.keeper(), keeper);
    }

    function test_deploy(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        IStrategyInterface stratStable = IStrategyInterface(
            strategyFactory.newPearlLPCompounder(
                tokenAddrs["USDC-USDR-lp"],
                "USDC-USDR-lp-compounder"
            )
        );
        IStrategyInterface stratVolatile = IStrategyInterface(
            strategyFactory.newPearlLPCompounder(
                tokenAddrs["WETH-USDR-lp"],
                "DAI-USDR-lp-compounder"
            )
        );
        IStrategyInterface stratStableNon3Pool = IStrategyInterface(
            strategyFactory.newPearlLPCompounder(
                tokenAddrs["STAR-USDR-lp"],
                "USDT-USDR-lp-compounder"
            )
        );
        IStrategyInterface stratPearl = IStrategyInterface(
            strategyFactory.newPearlLPCompounder(
                tokenAddrs["PEARL-USDR-lp"],
                "USDT-USDR-lp-compounder"
            )
        );

        strategy_testing(stratStable, _amount);
        strategy_testing(stratVolatile, _amount);
        strategy_testing(stratStableNon3Pool, _amount);
        strategy_testing(stratPearl, _amount);
    }

    function strategy_testing(
        IStrategyInterface _strategy,
        uint256 _amount
    ) internal {
        ERC20 _asset = ERC20(_strategy.asset());
        console.log(_amount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(_strategy, user, _amount, _asset);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(_strategy, _amount, _amount, 0);

        // Earn Interest
        skip(20 days);
        vm.roll(block.number + 1);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = _strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(_strategy.profitMaxUnlockTime());

        uint256 balanceBefore = _asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        _strategy.redeem(_amount, user, user);

        assertGe(
            _asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}

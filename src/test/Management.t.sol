// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

contract ManagementTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_setMinRewardsToSell() public {
        uint256 minRewardsToSell = 1;

        // user cannot change minRewardsToSell
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setMinRewardsToSell(minRewardsToSell);

        // management can change minRewardsToSell
        vm.prank(management);
        strategy.setMinRewardsToSell(minRewardsToSell);
        assertEq(strategy.minRewardsToSell(), minRewardsToSell);

        // verfiy amount cannot be above setMaxRewardsToSell
        uint256 maxRewardsToSell = strategy.maxRewardsToSell();
        vm.prank(management);
        vm.expectRevert("!minRewardsToSell");
        strategy.setMinRewardsToSell(maxRewardsToSell);
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
        // user cannot claimFees
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.claimFees();

        // management can  claimFees
        vm.prank(management);
        strategy.claimFees();
    }

    function test_claimAndSellRewards() public {
        // airdrop minimal amount of rewards
        deal(
            tokenAddrs["PEARL"],
            address(strategy),
            strategy.minRewardsToSell() + 1
        );

        // user cannot claimAndSellRewards
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.claimAndSellRewards();

        // management can claimAndSellRewards
        vm.prank(management);
        strategy.claimAndSellRewards();
    }

    function test_sweep() public {
        address gov = 0xC4ad0000E223E398DC329235e6C497Db5470B626;
        uint256 amount = 1e18;
        ERC20 airdropedToken = new ERC20("AIR", "AR");
        deal(address(airdropedToken), address(strategy), amount);

        // management cannot sweep
        vm.prank(management);
        vm.expectRevert("!governance");
        strategy.sweep(address(airdropedToken));

        // gov can sweep
        assertEq(airdropedToken.balanceOf(address(strategy)), amount);
        vm.prank(gov);
        strategy.sweep(address(airdropedToken));
        assertEq(airdropedToken.balanceOf(address(strategy)), 0);
        assertEq(airdropedToken.balanceOf(gov), amount);

        // gov cannot sweep asset
        vm.prank(gov);
        vm.expectRevert("!asset");
        strategy.sweep(address(asset));

        // gov cannot sweep PEARL
        vm.prank(gov);
        vm.expectRevert("!PEARL");
        strategy.sweep(tokenAddrs["PEARL"]);
    }

    function test_setUseCurve() public {
        // user cannot setUseCurveStable
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setUseCurveStable(true);

        // management can setUseCurveStable
        address assetAddress = address(asset);
        vm.prank(management);
        if (
            assetAddress == tokenAddrs["USDT-USDR-lp"] ||
            assetAddress == tokenAddrs["USDC-USDR-lp"]
        ) {
            strategy.setUseCurveStable(true);
            assertTrue(strategy.useCurveStable());
        } else {
            vm.expectRevert("!curveUnsupported");
            strategy.setUseCurveStable(true);
        }
    }

    function test_setSwapTokenRatio() public {
        uint256 swapTokenRatio = 20;

        // user cannot change swapTokenRatio
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setSwapTokenRatio(swapTokenRatio);

        // management can change swapTokenDiff
        vm.prank(management);
        strategy.setSwapTokenRatio(swapTokenRatio);
        assertEq(strategy.swapTokenRatio(), swapTokenRatio);

        // cannot change swapTokenRatio above fee dominator
        vm.prank(management);
        vm.expectRevert("!swapTokenRatio");
        strategy.setSwapTokenRatio(20001);

        // cannot change swapTokenRatio to 0
        vm.prank(management);
        vm.expectRevert("!swapTokenRatio");
        strategy.setSwapTokenRatio(0);
    }

    function test_setMaxRewardsToSell() public {
        uint256 maxRewardsToSell = type(uint256).max;

        // user cannot change maxRewardsToSell
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setMaxRewardsToSell(maxRewardsToSell);

        // management can change maxRewardsToSell
        vm.prank(management);
        strategy.setMaxRewardsToSell(maxRewardsToSell);
        assertEq(strategy.maxRewardsToSell(), maxRewardsToSell);

        // cannot change maxRewardsToSell below minRewardsToSell
        uint256 minRewardsToSell = strategy.minRewardsToSell();
        vm.prank(management);
        vm.expectRevert("!maxRewardsToSell");
        strategy.setMaxRewardsToSell(minRewardsToSell);
    }

    function test_setKeepPEARL() public {
        uint256 keepPearl = 20;

        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setKeepPEARLAddress(user);

        vm.prank(management);
        strategy.setKeepPEARLAddress(management);

        // user cannot change keepPearl
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setSwapTokenRatio(keepPearl);

        // management can change keepPearl
        vm.prank(management);
        strategy.setKeepPEARL(keepPearl);
        assertEq(strategy.keepPEARL(), keepPearl);

        // cannot change keepPearl above fee dominator
        vm.prank(management);
        vm.expectRevert("!keepPEARL");
        strategy.setKeepPEARL(10001);
    }
}

pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {PearlLPCompounderExt} from "./utils/PearlLPCompounderExt.sol";

contract InternalTest is Setup {
    PearlLPCompounderExt pearlLPCompounderExt;

    function setUp() public override {
        super.setUp();
    }

    function test_UsdrValueInDai() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDR"];
        uint256 amount = 1e9;
        uint256 valueInDai = pearlLPCompounderExt.getValueInDai(
            tokenIn,
            amount
        );
        assertEq(valueInDai, 1e18, "!valueInDai");
    }

    function test_UsdcValueInDai() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDC"];
        uint256 amount = 1e6;
        uint256 valueInDai = pearlLPCompounderExt.getValueInDai(
            tokenIn,
            amount
        );
        assertGt(valueInDai, 9e17, "!valueInDai");
        assertLt(valueInDai, 11e17, "!valueInDai");
    }

    function test_UsdtValueInDai() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDT"];
        uint256 amount = 1e6;
        uint256 valueInDai = pearlLPCompounderExt.getValueInDai(
            tokenIn,
            amount
        );
        assertGt(valueInDai, 9e17, "!valueInDai");
        assertLt(valueInDai, 11e17, "!valueInDai");
    }

    function test_WethValueInDai() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["WETH-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["WETH"];
        uint256 amount = 1e18;
        uint256 valueInDai = pearlLPCompounderExt.getValueInDai(
            tokenIn,
            amount
        );
        assertGt(valueInDai, 1000e18, "!valueInDai");
        assertLt(valueInDai, 3000e18, "!valueInDai");
    }

    function test_WbtcValueInDai() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["WBTC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["WBTC"];
        uint256 amount = 1e8;
        uint256 valueInDai = pearlLPCompounderExt.getValueInDai(
            tokenIn,
            amount
        );
        assertGt(valueInDai, 20000e18, "!valueInDai");
        assertLt(valueInDai, 40000e18, "!valueInDai");
    }

    function test_optimalAmountInPearl() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDC"];
        uint256 amount = 10e6;
        uint256 amountInPearl = pearlLPCompounderExt.getValueInPearl(
            tokenIn,
            amount
        );
        assertGt(amountInPearl, 1e18, "!amountInPearl");
        assertGt(amountInPearl, 1e19, "!amountInPearl");

        // without token in, same amount in pearl
        uint256 optimalAmountInPear = pearlLPCompounderExt
            .getOptimalSwapAmountInPearl(tokenIn, 0, amountInPearl);
        // no token, we need to swap all
        assertEq(optimalAmountInPear, amountInPearl, "!optimalAmountInPear");

        // airdrop 1/4 token in
        // deal(tokenIn, address(pearlLPCompounderExt), amount / 4);
        uint256 optimalAmountInPear2 = pearlLPCompounderExt
            .getOptimalSwapAmountInPearl(tokenIn, amount / 4, amountInPearl);
        // not enough token in, swap more than 1/2
        assertGt(
            optimalAmountInPear2,
            amountInPearl / 2,
            "!optimalAmountInPear2"
        );

        // airdrop token in
        // deal(tokenIn, address(pearlLPCompounderExt), amount);
        uint256 optimalAmountInPear3 = pearlLPCompounderExt
            .getOptimalSwapAmountInPearl(tokenIn, amount, amountInPearl);
        // enough token in, no swap
        assertEq(optimalAmountInPear3, 0, "!optimalAmountInPear3");
    }

    function test_getValueInPearl() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDC"];
        uint256 amount = 1e6;
        uint256 amountInPearl = pearlLPCompounderExt.getValueInPearl(
            tokenIn,
            amount
        );

        // $1 ~ 3 pearl
        assertGt(amountInPearl, 1e18, "!amountInPearlUSDC");
        assertLt(amountInPearl, 5e18, "!amountInPearlUSDC");

        // token in is usdr
        tokenIn = tokenAddrs["USDR"];
        amount = 1e9;
        amountInPearl = pearlLPCompounderExt.getValueInPearl(tokenIn, amount);
        assertGt(amountInPearl, 1e18, "!amountInPearlUSDR");
        assertLt(amountInPearl, 5e18, "!amountInPearlUSDR");
    }
}

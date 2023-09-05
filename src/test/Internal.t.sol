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
}

pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {PearlLPCompounderExt} from "./utils/PearlLPCompounderExt.sol";

contract InternalTest is Setup {
    PearlLPCompounderExt pearlLPCompounderExt;

    function setUp() public override {
        super.setUp();
    }

    function test_UsdrvalueInUsdr() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDR"];
        uint256 amount = 1e9;
        uint256 valueInUsdr = pearlLPCompounderExt.getValueInUSDR(
            tokenIn,
            amount
        );
        assertEq(valueInUsdr, amount, "!valueInUsdr");
    }

    function test_UsdcvalueInUsdr() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDC"];
        uint256 amount = 1e6;
        uint256 valueInUsdr = pearlLPCompounderExt.getValueInUSDR(
            tokenIn,
            amount
        );
        assertGt(valueInUsdr, 9e8, "!valueInUsdr");
        assertLt(valueInUsdr, 11e8, "!valueInUsdr");
    }

    function test_UsdtvalueInUsdr() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["USDC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["USDT"];
        uint256 amount = 1e6;
        uint256 valueInUsdr = pearlLPCompounderExt.getValueInUSDR(
            tokenIn,
            amount
        );
        assertGt(valueInUsdr, 9e8, "!valueInUsdr");
        assertLt(valueInUsdr, 11e8, "!valueInUsdr");
    }

    function test_WethvalueInUsdr() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["WETH-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["WETH"];
        uint256 amount = 1e18;
        uint256 valueInUsdr = pearlLPCompounderExt.getValueInUSDR(
            tokenIn,
            amount
        );
        assertGt(valueInUsdr, 1000e9, "!valueInUsdr");
        assertLt(valueInUsdr, 3000e9, "!valueInUsdr");
    }

    function test_WbtcvalueInUsdr() public {
        pearlLPCompounderExt = new PearlLPCompounderExt(
            tokenAddrs["WBTC-USDR-lp"],
            "PearlLPCompounderExt"
        );
        address tokenIn = tokenAddrs["WBTC"];
        uint256 amount = 1e8;
        uint256 valueInUsdr = pearlLPCompounderExt.getValueInUSDR(
            tokenIn,
            amount
        );
        assertGt(valueInUsdr, 20000e9, "!valueInUsdr");
        assertLt(valueInUsdr, 40000e9, "!valueInUsdr");
    }
}

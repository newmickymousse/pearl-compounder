// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PearlLPCompounderFactory} from "../../PearlLPCompounderFactory.sol";
import {PearlLPCompounder} from "../../PearlLPCompounder.sol";
import {IStrategyFactoryInterface} from "../../interfaces/IStrategyFactoryInterface.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instancees that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;
    IStrategyFactoryInterface public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 5_000e15;

    // Default prfot max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        asset = ERC20(tokenAddrs["USDC-USDR-lp"]);
        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(
            strategyFactory.newPearlLPCompounder(
                address(asset),
                "AMM - USDR/USDT"
            )
        );
        setUpStrategy();

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(address(strategyFactory), "strategyFactory");
        vm.label(address(user), "user");
    }

    function setUpStrategyFactory() public returns (IStrategyFactoryInterface) {
        IStrategyFactoryInterface _factory = IStrategyFactoryInterface(
            address(
                new PearlLPCompounderFactory(
                    management,
                    performanceFeeRecipient,
                    keeper
                )
            )
        );
        return _factory;
    }

    function setUpStrategy() public {
        vm.prank(management);
        strategy.acceptManagement();
        vm.prank(management);
        strategy.setMaxRewardsToSell(type(uint256).max);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        depositIntoStrategy(_strategy, _user, _amount, asset);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount,
        ERC20 _asset
    ) public {
        vm.prank(_user);
        _asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        mintAndDepositIntoStrategy(_strategy, _user, _amount, asset);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount,
        ERC20 _asset
    ) public {
        airdrop(_asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount, _asset);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertEq(_strategy.totalAssets(), _totalAssets, "!totalAssets");
        assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.startPrank(management);
        strategy.setPerformanceFee(_performanceFee);
        strategy.setKeepPEARLAddress(management);
        strategy.setKeepPEARL(1000); // set keepPEARL to 10%
        // strategy.setUseCurveStable(true); // use curve instead of synapse
        vm.stopPrank();
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
        tokenAddrs["WETH"] = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        tokenAddrs["USDT"] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        tokenAddrs["DAI"] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        tokenAddrs["USDC"] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        tokenAddrs["USDR"] = 0x40379a439D4F6795B6fc9aa5687dB461677A2dBa;
        tokenAddrs["PEARL"] = 0x7238390d5f6F64e67c3211C343A410E2A3DEc142;
        tokenAddrs["USDC-USDR-lp"] = 0xD17cb0f162f133e339C0BbFc18c36c357E681D6b;
        tokenAddrs["DAI-USDR-lp"] = 0xBD02973b441Aa83c8EecEA158b98B5984bb1036E;
        tokenAddrs["USDT-USDR-lp"] = 0x3f69055F203861abFd5D986dC81a2eFa7c915b0c;
        tokenAddrs["WETH-USDR-lp"] = 0x74c64d1976157E7Aaeeed46EF04705F4424b27eC;
        tokenAddrs["WBTC-USDR-lp"] = 0xb95E1C22dd965FafE926b2A793e9D6757b6613F4;
        tokenAddrs[
            "WMATIC-USDR-lp"
        ] = 0xB4d852b92148eAA16467295975167e640E1FE57A;
        tokenAddrs["STAR-USDR-lp"] = 0x366dc82D3BFFd482cc405E58bAb3288F2dd32C94;
        tokenAddrs[
            "fxDOLA-USDR-lp"
        ] = 0x8B0630Cb57d8E63444E97C19a2e82Bb1988399e2;
        tokenAddrs[
            "PEARL-USDR-lp"
        ] = 0xf68c20d6C50706f6C6bd8eE184382518C93B368c;
        tokenAddrs["PEARL-CRV-lp"] = 0x700D6E1167472bDc312D9cBBdc7c58C7f4F45120;
    }
}

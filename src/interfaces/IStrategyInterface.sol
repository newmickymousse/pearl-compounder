// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function setKeepPEARL(uint256 _keepPEARL, address _voter) external;

    function setMinRewardsToSell(uint256 _minRewardsToSell) external;

    function minRewardsToSell() external view returns (uint256);

    function getClaimableRewards() external view returns (uint256);

    function getRewardsValue() external view returns (uint256);

    function setSlippageStable(uint256 _slippageStable) external;

    function slippageStable() external view returns (uint256);

    function reportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);

    function sweep(address _token) external;

    function claimAndSellRewards() external;

    function claimFees() external;

    function setUseCurveStable(bool _useCurveStable) external;

    function useCurveStable() external view returns (bool);
}

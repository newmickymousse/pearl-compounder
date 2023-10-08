// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function setKeepPEARL(uint256 _keepPEARL) external;

    function setKeepPEARLAddress(address _keepPEARLAddress) external;

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

    function setMinFeesToClaim(uint256 _minFeesToClaim) external;

    function minFeesToClaim() external view returns (uint256);

    function setSwapTokenRatio(uint256 _swapTokenRatio) external;

    function swapTokenRatio() external view returns (uint256);

    function setMaxRewardsToSell(uint256 _maxRewardsToSell) external;

    function maxRewardsToSell() external view returns (uint256);

    function balanceOfRewards() external view returns (uint256);
}

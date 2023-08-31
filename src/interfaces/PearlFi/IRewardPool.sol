// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IRewardPool {
    function deposit(uint256 amount) external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function earned(address account) external view returns (uint256);

    function getReward() external;

    function balanceOf(address account) external view returns (uint256);

    function stakingToken() external view returns (address);

    function rewardsToken() external view returns (address);

    function emergency() external view returns (bool);

    function emergencyWithdraw() external;
}

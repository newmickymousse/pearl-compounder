// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function setKeepPEARL(uint256 _keepPEARL) external;
    function report() external returns (uint256 profit, uint256 loss);
    function asset() external view returns (address);
}

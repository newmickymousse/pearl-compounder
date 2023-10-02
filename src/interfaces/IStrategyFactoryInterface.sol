// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IStrategyFactoryInterface {
    function newPearlLPCompounder(
        address _asset,
        string memory _name
    ) external returns (address);

    function newPearlLPCompounderPermissioned(
        address _asset,
        string memory _name
    ) external returns (address);

    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);

    function getStrategiesLength() external view returns (uint256);

    function strategies(uint256) external view returns (address);
}

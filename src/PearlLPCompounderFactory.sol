// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {PearlLPCompounder} from "./PearlLPCompounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract PearlLPCompounderFactory {
    event NewPearlLPCompounder(address indexed strategy, address indexed asset);
    event NewPearlLPCompounderPerimssioned(
        address indexed strategy,
        address indexed asset
    );

    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address[] public strategies;

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        performanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }

    /**
     * @notice Deploy a new Pearl Stable LP Compounder Strategy.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newPearlLPCompounder(
        address _asset,
        string memory _name
    ) external returns (address) {
        address newStrategy = _newPearlLPCompounder(_asset, _name);
        emit NewPearlLPCompounder(address(newStrategy), _asset);
        return newStrategy;
    }

    /**
     * @notice Deploy a new Pearl Stable LP Compounder Strategy. Adds strategy to strategies array.
     * @dev Only management can call this function.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newPearlLPCompounderPermissioned(
        address _asset,
        string memory _name
    ) external onlyManagement returns (address) {
        address newStrategy = _newPearlLPCompounder(_asset, _name);
        strategies.push(newStrategy);
        emit NewPearlLPCompounderPerimssioned(newStrategy, _asset);
        return newStrategy;
    }

    /**
     * @notice Set the management address.
     * @dev This is the address that can call the management functions.
     * @param _management The address to set as the management address.
     */
    function setManagement(address _management) external onlyManagement {
        require(_management != address(0), "ZERO_ADDRESS");
        management = _management;
    }

    /**
     * @notice Set the performance fee recipient address.
     * @dev This is the address that will receive the performance fee.
     * @param _performanceFeeRecipient The address to set as the performance fee recipient address.
     */
    function setPerformanceFeeRecipient(
        address _performanceFeeRecipient
    ) external onlyManagement {
        require(_performanceFeeRecipient != address(0), "ZERO_ADDRESS");
        performanceFeeRecipient = _performanceFeeRecipient;
    }

    /**
     * @notice Set the keeper address.
     * @dev This is the address that will be able to call the keeper functions.
     * @param _keeper The address to set as the keeper address.
     */
    function setKeeper(address _keeper) external onlyManagement {
        keeper = _keeper;
    }

    /**
     * @notice Get the number of strategies depolyed.
     * @return . Total number of strategies.
     */
    function getStrategiesLength() external view returns (uint256) {
        return strategies.length;
    }

    function _newPearlLPCompounder(
        address _asset,
        string memory _name
    ) internal returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new PearlLPCompounder(_asset, _name))
        );
        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        newStrategy.setKeeper(keeper);
        newStrategy.setPendingManagement(management);

        return address(newStrategy);
    }
}

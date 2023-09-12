// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {PearlLPCompounder} from "./PearlLPCompounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract PearlLPCompounderFactory {
    event NewPearlLPCompounder(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        performanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
    }

    /**
     * @notice Deploy a new Pearl Stable LP Compounder Strategy.
     * @dev This will set the msg.sender to all of the permissioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newPearlLPCompounder(
        address _asset,
        string memory _name
    ) external returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new PearlLPCompounder(_asset, _name))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        // Review: keep pearl is defaulted at 0 in the strat code.
        // I would remove this line.
        newStrategy.setKeepPEARL(0, management);

        emit NewPearlLPCompounder(address(newStrategy), _asset);
        return address(newStrategy);
    }

    // Review, why setter functions setting more than one value?
    // Why there isn't a separated setMgmt, setPerformance..., setKeeper?
    function setAddresses(
        address _management,
        address _perfomanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _perfomanceFeeRecipient;
        keeper = _keeper;
    }
}

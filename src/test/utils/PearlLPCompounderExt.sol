// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {PearlLPCompounder} from "../../PearlLPCompounder.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specifc storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be udpated post deployement will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement and onlyKeepers modifiers

contract PearlLPCompounderExt is PearlLPCompounder {
    constructor(
        address _asset,
        string memory _name
    ) PearlLPCompounder(_asset, _name) {}

    function getValueInDai(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        return _getValueInDAI(_token, _amount);
    }

    function getValueInPearl(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        return _getValueInPearl(_token, _amount);
    }

    function getOptimalSwapAmountInPearl(
        address _token,
        uint256 _tokenBalance,
        uint256 _amount
    ) public view returns (uint256) {
        return _getOptimalSwapAmountInPearl(_token, _tokenBalance, _amount);
    }
}

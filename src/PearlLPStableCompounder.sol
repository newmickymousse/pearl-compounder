// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";
import {BaseHealthCheck} from "@periphery/HealthCheck/BaseHealthCheck.sol";
import {CustomStrategyTriggerBase} from "@periphery/ReportTrigger/CustomStrategyTriggerBase.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPearlRouter} from "./interfaces/PearlFi/IPearlRouter.sol";
import {IPair} from "./interfaces/PearlFi/IPair.sol";
import {IRewardPool} from "./interfaces/PearlFi/IRewardPool.sol";
import {IVoter} from "./interfaces/PearlFi/IVoter.sol";
import {IUSDRExchange} from "./interfaces/Tangible/IUSDRExchange.sol";
import {IStableSwapPool} from "./interfaces/Synapse/IStableSwapPool.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

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

contract PearlLPStableCompounder is BaseHealthCheck, CustomStrategyTriggerBase {
    using SafeERC20 for ERC20;

    IUSDRExchange constant usdrExchange =
        IUSDRExchange(0x195F7B233947d51F4C3b756ad41a5Ddb34cEBCe0);
    IPearlRouter constant pearlRouter =
        IPearlRouter(0xcC25C0FD84737F44a7d38649b69491BBf0c7f083); // use value from: https://docs.pearl.exchange/protocol-details/contract-addresses-v1.5
    IVoter constant pearlVoter =
        IVoter(0xa26C2A6BfeC5512c13Ae9EacF41Cb4319d30cCF0);
    IStableSwapPool constant synapseStablePool =
        IStableSwapPool(0x85fCD7Dd0a1e1A9FCD5FD886ED522dE8221C3EE5);
    IRewardPool immutable pearlRewards;
    IPair private immutable lpToken;
    bool public immutable isStable;

    ERC20 public constant usdr =
        ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);
    ERC20 public constant pearl =
        ERC20(0x7238390d5f6F64e67c3211C343A410E2A3DEc142);
    ERC20 public constant DAI =
        ERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);

    uint256 public constant FEE_DENOMINATOR = 10_000; // keepPEARL is in bps
    uint256 public keepPEARL = 0; // the percentage of PEARL we re-lock for boost (in basis points)
    uint256 public minRewardsToSell = 30e18; // ~ $9
    uint256 public slippage = 500; // 5% slippage in BPS
    uint256 public slippageStable = 50; // 0.5% slippage in BPS

    constructor(
        address _asset,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {
        lpToken = IPair(_asset);
        address _gauge = pearlVoter.gauges(_asset);
        require(_gauge != address(0), "!gauge");
        pearlRewards = IRewardPool(_gauge);

        // ERC20(asset).safeApprove(address(router), type(uint256).max);
        ERC20(asset).safeIncreaseAllowance(
            address(pearlRewards),
            type(uint256).max
        );
        ERC20(lpToken.token0()).safeIncreaseAllowance(
            address(pearlRouter),
            type(uint256).max
        );
        ERC20(lpToken.token1()).safeIncreaseAllowance(
            address(pearlRouter),
            type(uint256).max
        );

        ERC20(usdr).safeIncreaseAllowance(
            address(usdrExchange),
            type(uint256).max
        );
        ERC20(pearl).safeIncreaseAllowance(
            address(pearlRouter),
            type(uint256).max
        );

        isStable = lpToken.stable();
        if (isStable) {
            // approve synapse pool for stables only
            ERC20(DAI).safeIncreaseAllowance(
                address(usdrExchange),
                type(uint256).max
            );
            ERC20(DAI).safeIncreaseAllowance(
                address(synapseStablePool),
                type(uint256).max
            );
            if (lpToken.token0() != address(DAI)) {
                ERC20(lpToken.token0()).safeIncreaseAllowance(
                    address(synapseStablePool),
                    type(uint256).max
                );
            }
            if (lpToken.token1() != address(DAI)) {
                ERC20(lpToken.token1()).safeIncreaseAllowance(
                    address(synapseStablePool),
                    type(uint256).max
                );
            }
        }
    }

    // Set the amount of PEARL to be locked in Yearn's vePEARL voter from each harvest
    function setKeepPEARL(uint256 _keepPEARL) external onlyManagement {
        keepPEARL = _keepPEARL;
    }

    /// @notice Set the amount of PEARL to be sold for asset from each harvest
    /// @param _minRewardsToSell amount of PEARL to be sold for asset from each harvest
    function setMinRewardsToSell(
        uint256 _minRewardsToSell
    ) external onlyManagement {
        minRewardsToSell = _minRewardsToSell;
    }

    /// @notice Set the slippage for selling PEARL to volatile token in asset
    /// @param _slippage slippage in BPS
    function setSlippage(uint256 _slippage) external onlyManagement {
        require(_slippage < FEE_DENOMINATOR, "!slippage");
        slippage = _slippage;
    }

    /// @notice Set slippage for swapping stable to stable
    /// @param _slippageStable slippage in BPS
    function setSlippageStable(
        uint256 _slippageStable
    ) external onlyManagement {
        require(_slippageStable < FEE_DENOMINATOR, "!slippageStable");
        slippageStable = _slippageStable;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        uint256 balanceOfLp = balanceOfAsset();

        pearlRewards.deposit(_amount > balanceOfLp ? balanceOfLp : _amount);
    }

    function balanceOfAsset() public view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function balanceOfStakedAssets() public view returns (uint256) {
        return pearlRewards.balanceOf(address(this));
    }

    function balanceOfRewards() public view returns (uint256) {
        return pearl.balanceOf(address(this));
    }

    /// @notice Get pending value of rewards in DAI
    /// @return value of pearl in DAI
    function getClaimableRewards() external view returns (uint256) {
        uint256 pendingPearl = pearlRewards.earned(address(this));
        return _getValueOfPearlInDai(pendingPearl);
    }

    /// @notice Get value of rewards in DAI
    /// @return value of pearl in DAI
    function getRewardsValue() external view returns (uint256) {
        uint256 pearlBalance = pearl.balanceOf(address(this));
        return _getValueOfPearlInDai(pearlBalance);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        uint256 balanceOfStakedLp = balanceOfStakedAssets();

        pearlRewards.withdraw(
            _amount > balanceOfStakedLp ? balanceOfStakedLp : _amount
        );
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            _claimAndSellRewards();

            // check if we got someting from selling the loot and deploy it
            uint256 _balanceOfAsset = balanceOfAsset();
            if (_balanceOfAsset > 0) {
                _deployFunds(_balanceOfAsset);
            }
        }
        _totalAssets = balanceOfAsset() + balanceOfStakedAssets();

        _executeHealthCheck(_totalAssets);
    }

    /**
     * @notice Returns wether or not report() should be called by a keeper.
     * @dev Check if there are idle assets, if the strategy is not shutdown
     * and if there are any rewards to be claimed.
     *
     * @return . Should return true if report() should be called by keeper or false if not.
     */
    function reportTrigger(
        address /*_strategy*/
    ) external view override returns (bool, bytes memory) {
        if (TokenizedStrategy.isShutdown()) return (false, bytes("Shutdown"));
        // gas cost is not concern here
        if (balanceOfAsset() > 0 || balanceOfRewards() > minRewardsToSell) {
            return (
                true,
                abi.encodeWithSelector(TokenizedStrategy.report.selector)
            );
        }

        return (
            // Return true is the full profit unlock time has passed since the last report.
            block.timestamp - TokenizedStrategy.lastReport() >
                TokenizedStrategy.profitMaxUnlockTime(),
            // Return the report function sig as the calldata.
            abi.encodeWithSelector(TokenizedStrategy.report.selector)
        );
    }

    function _getLPReserves()
        internal
        view
        returns (
            address tokenA,
            address tokenB,
            uint256 reservesTokenA,
            uint256 reservesTokenB
        )
    {
        tokenA = lpToken.token0();
        tokenB = lpToken.token1();
        (reservesTokenA, reservesTokenB, ) = lpToken.getReserves();
    }

    function _getValueInDAI(
        address token,
        uint256 _amount
    ) internal view returns (uint256 amountInDAI) {
        if (token == address(DAI) || token == address(usdr)) {
            return _amount;
        }

        if (isStable) {
            uint8 tokenId = synapseStablePool.getTokenIndex(token);
            uint8 daiId = synapseStablePool.getTokenIndex(address(DAI));
            amountInDAI = synapseStablePool.calculateSwap(
                tokenId,
                daiId,
                _amount
            );
        } else {
            // use DAI == USDR because it's used only for adding liquidity to pool
            (amountInDAI, ) = pearlRouter.getAmountOut(
                _amount,
                token,
                address(usdr)
            );
        }
    }

    function _swapPearlForToken(address _tokenOut, uint256 _amountIn) internal {
        if (_tokenOut != address(pearl) && _amountIn > 0) {
            uint256 minAmountOut = _getMinAmountOut(
                address(pearl),
                address(usdr),
                _amountIn
            );
            uint256[] memory usdrOut = pearlRouter
                .swapExactTokensForTokensSimple(
                    _amountIn,
                    minAmountOut,
                    address(pearl),
                    address(usdr),
                    false,
                    address(this),
                    block.timestamp
                );

            if (_tokenOut != address(usdr)) {
                //if we need anything but USDR, let's withdraw from tangible to get DAI first
                if (isStable) {
                    uint256 daiOut = usdrExchange.swapToUnderlying(
                        usdrOut[1],
                        address(this)
                    );

                    if (_tokenOut != address(DAI)) {
                        uint8 daiId = synapseStablePool.getTokenIndex(
                            address(DAI)
                        );
                        uint8 tokenOutId = synapseStablePool.getTokenIndex(
                            _tokenOut
                        );
                        uint256 minOut = (synapseStablePool.calculateSwap(
                            daiId,
                            tokenOutId,
                            daiOut
                        ) * (FEE_DENOMINATOR - slippageStable)) /
                            FEE_DENOMINATOR;
                        synapseStablePool.swap(
                            daiId,
                            tokenOutId,
                            daiOut,
                            minOut,
                            block.timestamp
                        );
                    }
                } else {
                    uint256 usdrBalance = usdrOut[1];
                    minAmountOut = _getMinAmountOut(
                        address(usdr),
                        _tokenOut,
                        usdrBalance
                    );
                    pearlRouter.swapExactTokensForTokensSimple(
                        usdrBalance,
                        minAmountOut,
                        address(usdr),
                        _tokenOut,
                        false,
                        address(this),
                        block.timestamp
                    );
                }
            }
        }
    }

    function _getMinAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 minAmountOut) {
        (minAmountOut, ) = pearlRouter.getAmountOut(
            _amountIn,
            _tokenIn,
            _tokenOut
        );
        minAmountOut =
            (minAmountOut * (FEE_DENOMINATOR - slippage)) /
            FEE_DENOMINATOR;
    }

    function _getValueOfPearlInDai(
        uint256 _amount
    ) internal view returns (uint256) {
        IPearlRouter.route[] memory routes = new IPearlRouter.route[](2);
        routes[0] = IPearlRouter.route(address(pearl), address(usdr), false);
        routes[1] = IPearlRouter.route(address(usdr), address(DAI), true);
        uint256[] memory amounts = pearlRouter.getAmountsOut(_amount, routes);
        return amounts[2]; // 3 amounts, use the last one
    }

    function _claimAndSellRewards() internal {
        uint256 pearlBalanceBefore = pearl.balanceOf(address(this));

        // claim lp fees
        lpToken.claimFees();

        // get PEARL, sell them for asset
        pearlRewards.getReward();
        uint256 pearlBalance = pearl.balanceOf(address(this));
        if (pearlBalance > minRewardsToSell) {
            if (keepPEARL > 0 && pearlBalance - pearlBalanceBefore > 0) {
                pearl.safeTransfer(
                    TokenizedStrategy.management(),
                    ((pearlBalance - pearlBalanceBefore) * keepPEARL) /
                        FEE_DENOMINATOR
                );
            }

            pearlBalance = pearl.balanceOf(address(this));

            // get lp reserves
            (
                address tokenA,
                address tokenB,
                uint256 reservesTokenA,
                uint256 reservesTokenB
            ) = _getLPReserves();

            // value reserves to DAI
            uint256 reservesAinDAI = _getValueInDAI(tokenA, reservesTokenA);
            uint256 reservesBinDAI = _getValueInDAI(tokenB, reservesTokenB);

            // calculate proportion & quote needs from pearl
            uint256 totalInDAI = reservesAinDAI + reservesBinDAI;
            uint256 pearlToTokenA = (pearlBalance * reservesAinDAI) /
                totalInDAI;
            uint256 pearlToTokenB = (pearlBalance * reservesBinDAI) /
                totalInDAI;
            // sell pearl to each asset
            if (pearlToTokenA > 0) {
                _swapPearlForToken(tokenA, pearlToTokenA);
            }
            if (pearlToTokenB > 0) {
                _swapPearlForToken(tokenB, pearlToTokenB);
            }

            // build lp
            if (
                ERC20(tokenA).balanceOf(address(this)) > 0 &&
                ERC20(tokenA).balanceOf(address(this)) > 0
            ) {
                pearlRouter.addLiquidity(
                    tokenA,
                    tokenB,
                    isStable,
                    ERC20(tokenA).balanceOf(address(this)),
                    ERC20(tokenB).balanceOf(address(this)),
                    1,
                    1,
                    address(this),
                    block.timestamp
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deploy idle funds.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal override {
        _deployFunds(_totalIdle);
    }

    /**
     * @notice Returns wether or not tend() should be called by a keeper.
     * @dev Check if there idle assets and if the strategy is not shutdown.
     *
     * @return shouldTend Should return true if tend() should be called by keeper or false if not.
     */
    function tendTrigger() public view override returns (bool shouldTend) {
        if (
            !TokenizedStrategy.isShutdown() && TokenizedStrategy.totalIdle() > 0
        ) {
            shouldTend = true;
        }
    }

    /**
     * @dev Withdraw funds from gauge
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }
}

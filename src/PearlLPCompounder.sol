// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

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

contract PearlLPCompounder is BaseHealthCheck, CustomStrategyTriggerBase {
    using SafeERC20 for ERC20;

    IUSDRExchange private constant USDR_EXCHANGE =
        IUSDRExchange(0x195F7B233947d51F4C3b756ad41a5Ddb34cEBCe0);
    IPearlRouter private constant PEARL_ROUTER =
        IPearlRouter(0xcC25C0FD84737F44a7d38649b69491BBf0c7f083); // use value from: https://docs.pearl.exchange/protocol-details/contract-addresses-v1.5
    IStableSwapPool private constant SYNAPSE_STABLE_POOL =
        IStableSwapPool(0x85fCD7Dd0a1e1A9FCD5FD886ED522dE8221C3EE5);

    ERC20 private constant USDR =
        ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);
    ERC20 private constant PEARL =
        ERC20(0x7238390d5f6F64e67c3211C343A410E2A3DEc142);
    ERC20 private constant DAI =
        ERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);

    address private constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52; //yearn governance
    uint256 private constant USDR_TO_DAI_PRECISION = 1e9;

    IRewardPool private immutable pearlRewards;
    IPair private immutable lpToken;
    bool private immutable isStable;

    uint256 public keepPEARL; // 0 is default. the percentage of PEARL we re-lock for boost (in basis points)
    uint256 public minRewardsToSell = 30e18; // ~ $9
    uint256 public slippageStable = 50; // 0.5% slippage in BPS
    /// @notice The address of PEARL voter. This is where we send any keepPEARL.
    address public voter;

    event PearlCompounderCreated(
        address indexed lpToken,
        bool isStable,
        address rewards
    );

    constructor(
        address _asset,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {
        lpToken = IPair(_asset);
        IVoter pearlVoter = IVoter(0xa26C2A6BfeC5512c13Ae9EacF41Cb4319d30cCF0);
        address _gauge = pearlVoter.gauges(_asset);
        require(_gauge != address(0), "!gauge");
        pearlRewards = IRewardPool(_gauge);

        ERC20(asset).safeApprove(address(pearlRewards), type(uint256).max);
        ERC20(lpToken.token0()).safeApprove(
            address(PEARL_ROUTER),
            type(uint256).max
        );
        ERC20(lpToken.token1()).safeApprove(
            address(PEARL_ROUTER),
            type(uint256).max
        );

        USDR.safeApprove(address(USDR_EXCHANGE), type(uint256).max);
        PEARL.safeApprove(address(PEARL_ROUTER), type(uint256).max);

        isStable = lpToken.stable();
        if (isStable) {
            // approve synapse pool for stables only
            DAI.safeApprove(address(SYNAPSE_STABLE_POOL), type(uint256).max);
            if (lpToken.token0() != address(DAI)) {
                ERC20(lpToken.token0()).safeApprove(
                    address(SYNAPSE_STABLE_POOL),
                    type(uint256).max
                );
            }
            if (lpToken.token1() != address(DAI)) {
                ERC20(lpToken.token1()).safeApprove(
                    address(SYNAPSE_STABLE_POOL),
                    type(uint256).max
                );
            }
        }

        emit PearlCompounderCreated(_asset, isStable, _gauge);
    }

    /// @notice Set the amount and address of PEARL to be locked in Yearn's vePEARL voter from each harvest
    /// @dev cannot be zero address
    /// @param _keepPEARL amount of PEARL to be locked
    /// @param _voter address of PEARL voter
    function setKeepPEARL(
        uint256 _keepPEARL,
        address _voter
    ) external onlyManagement {
        require(_voter != address(0), "!voter");
        voter = _voter;
        keepPEARL = _keepPEARL;
    }

    /// @notice Set the amount of PEARL to be sold for asset from each harvest
    /// @param _minRewardsToSell amount of PEARL to be sold for asset from each harvest
    function setMinRewardsToSell(
        uint256 _minRewardsToSell
    ) external onlyManagement {
        minRewardsToSell = _minRewardsToSell;
    }

    /// @notice Set slippage for swapping stable to stable
    /// @param _slippageStable slippage in BPS
    function setSlippageStable(
        uint256 _slippageStable
    ) external onlyManagement {
        require(_slippageStable < MAX_BPS, "!slippageStable");
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
        pearlRewards.deposit(_amount);
    }

    function balanceOfAsset() public view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function balanceOfStakedAssets() public view returns (uint256) {
        return pearlRewards.balanceOf(address(this));
    }

    function balanceOfRewards() public view returns (uint256) {
        return PEARL.balanceOf(address(this));
    }

    /// @notice Get pending value of rewards in DAI
    /// @return value of PEARL in DAI
    function getClaimableRewards() external view returns (uint256) {
        uint256 pendingPearl = pearlRewards.earned(address(this));
        return _getValueOfPearlInDai(pendingPearl);
    }

    /// @notice Get value of rewards in DAI
    /// @return value of PEARL in DAI
    function getRewardsValue() external view returns (uint256) {
        uint256 pearlBalance = PEARL.balanceOf(address(this));
        return _getValueOfPearlInDai(pearlBalance);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        pearlRewards.withdraw(_amount);
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address //_owner
    ) public view override returns (uint256) {
        return balanceOfStakedAssets() + TokenizedStrategy.totalIdle();
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
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            // claim lp fees
            lpToken.claimFees();

            // check if we have enough rewards pending to sell
            if (
                pearlRewards.earned(address(this)) + balanceOfRewards() >
                minRewardsToSell
            ) {
                _claimAndSellRewards();
            }
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
        if (
            balanceOfAsset() > 0 ||
            pearlRewards.earned(address(this)) + balanceOfRewards() >
            minRewardsToSell
        ) {
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
        if (token == address(DAI)) {
            return _amount;
        }
        if (token == address(USDR)) {
            return _amount * USDR_TO_DAI_PRECISION;
        }

        if (isStable) {
            uint8 tokenId = SYNAPSE_STABLE_POOL.getTokenIndex(token);
            uint8 daiId = SYNAPSE_STABLE_POOL.getTokenIndex(address(DAI));
            amountInDAI = SYNAPSE_STABLE_POOL.calculateSwap(
                tokenId,
                daiId,
                _amount
            );
        } else {
            // use DAI == USDR because it's used only for adding liquidity to pool
            (amountInDAI, ) = PEARL_ROUTER.getAmountOut(
                _amount,
                token,
                address(USDR)
            );
            amountInDAI = amountInDAI * USDR_TO_DAI_PRECISION;
        }
    }

    function _swapPearlForToken(
        address _tokenOut,
        uint256 _amountIn
    ) internal returns (uint256) {
        if (_tokenOut != address(PEARL) && _amountIn > 0) {
            uint256 usdrOut = PEARL_ROUTER.swapExactTokensForTokensSimple(
                _amountIn,
                0,
                address(PEARL),
                address(USDR),
                false,
                address(this),
                block.timestamp
            )[1];

            if (_tokenOut != address(USDR)) {
                //if we need anything but USDR, let's withdraw from tangible or sell on pearl to get DAI first
                if (isStable) {
                    return _swapStable(_tokenOut, usdrOut);
                } else {
                    return
                        PEARL_ROUTER.swapExactTokensForTokensSimple(
                            usdrOut,
                            0,
                            address(USDR),
                            _tokenOut,
                            false,
                            address(this),
                            block.timestamp
                        )[1];
                }
            }
            return usdrOut;
        }
    }

    function _swapStable(
        address _tokenOut,
        uint256 _usdrAmount
    ) internal returns (uint256) {
        uint256 daiOut = _swapToUnderlying(_usdrAmount);

        if (_tokenOut != address(DAI)) {
            uint8 daiId = SYNAPSE_STABLE_POOL.getTokenIndex(address(DAI));
            uint8 tokenOutId = SYNAPSE_STABLE_POOL.getTokenIndex(_tokenOut);
            uint256 minAmountOut = (daiOut * (MAX_BPS - slippageStable)) /
                MAX_BPS;

            // remove decimals if needed
            uint256 tokenOutDecimals = ERC20(_tokenOut).decimals();
            if (tokenOutDecimals < 18) {
                minAmountOut = minAmountOut / 10 ** (18 - tokenOutDecimals);
            }
            return
                SYNAPSE_STABLE_POOL.swap(
                    daiId,
                    tokenOutId,
                    daiOut,
                    minAmountOut,
                    block.timestamp
                );
        }
    }

    function _swapToUnderlying(uint256 _usdrAmount) internal returns (uint256) {
        // Get the expected amount of `asset` out with the withdrawal fee.
        uint256 outWithFee = (_usdrAmount -
            ((_usdrAmount * USDR_EXCHANGE.withdrawalFee()) / MAX_BPS)) *
            USDR_TO_DAI_PRECISION;

        // If we can get more from the Pearl pool use that.
        (uint256 daiSwap, bool stable) = PEARL_ROUTER.getAmountOut(
            _usdrAmount,
            address(USDR),
            address(DAI)
        );
        if (daiSwap > outWithFee) {
            return
                PEARL_ROUTER.swapExactTokensForTokensSimple(
                    _usdrAmount,
                    outWithFee,
                    address(USDR),
                    address(DAI),
                    stable,
                    address(this),
                    block.timestamp
                )[1];
        } else {
            return USDR_EXCHANGE.swapToUnderlying(_usdrAmount, address(this));
        }
    }

    function _getValueOfPearlInDai(
        uint256 _amount
    ) internal view returns (uint256) {
        IPearlRouter.route[] memory routes = new IPearlRouter.route[](2);
        routes[0] = IPearlRouter.route(address(PEARL), address(USDR), false);
        routes[1] = IPearlRouter.route(address(USDR), address(DAI), true);
        uint256[] memory amounts = PEARL_ROUTER.getAmountsOut(_amount, routes);
        return amounts[2]; // 3 amounts, use the last one
    }

    function _claimAndSellRewards() internal {
        uint256 pearlBalance = _claimRewards();

        // get lp reserves
        (
            address tokenA,
            address tokenB,
            uint256 reservesTokenA,
            uint256 reservesTokenB
        ) = _getLPReserves();

        uint256 tokenBalanceA = ERC20(tokenA).balanceOf(address(this));
        uint256 tokenBalanceB = ERC20(tokenB).balanceOf(address(this));

        // value reserves to DAI, account in strategy token holdings
        uint256 reservesAinDAI = _getValueInDAI(
            tokenA,
            reservesTokenA + tokenBalanceA
        );
        uint256 reservesBinDAI = _getValueInDAI(
            tokenB,
            reservesTokenB + tokenBalanceB
        );

        // calculate proportion & quote needs from PEARL
        uint256 totalInDAI = reservesAinDAI + reservesBinDAI;
        uint256 pearlToTokenA = (pearlBalance * reservesAinDAI) / totalInDAI;
        uint256 pearlToTokenB = (pearlBalance * reservesBinDAI) / totalInDAI;

        // sell PEARL to each asset
        if (pearlToTokenA > 0) {
            tokenBalanceA += _swapPearlForToken(tokenA, pearlToTokenA);
        }
        if (pearlToTokenB > 0) {
            tokenBalanceB += _swapPearlForToken(tokenB, pearlToTokenB);
        }

        // build lp
        PEARL_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            isStable,
            tokenBalanceA,
            tokenBalanceB,
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    function _claimRewards() internal returns (uint256) {
        uint256 pearlBalanceBefore = PEARL.balanceOf(address(this));
        pearlRewards.getReward();
        uint256 pearlBalance = PEARL.balanceOf(address(this));

        if (keepPEARL > 0 && pearlBalance - pearlBalanceBefore > 0) {
            PEARL.safeTransfer(
                voter,
                ((pearlBalance - pearlBalanceBefore) * keepPEARL) / MAX_BPS
            );
            pearlBalance = PEARL.balanceOf(address(this));
        }
        return pearlBalance;
    }

    function claimFees() external onlyManagement {
        lpToken.claimFees();
    }

    function claimAndSellRewards() external onlyManagement {
        _claimAndSellRewards();
    }

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
        uint256 balanceOfStakedLp = balanceOfStakedAssets();
        // avoid possible reverts
        pearlRewards.withdraw(
            _amount > balanceOfStakedLp ? balanceOfStakedLp : _amount
        );
    }

    /// @notice Sweep all ERC20 tokens to the management
    /// @dev Cannot sweep the tokenized asset or PEARL, only callable by governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!governance");
        require(_token != asset, "!asset");
        require(_token != address(PEARL), "!PEARL");
        ERC20 token = ERC20(_token);
        token.safeTransfer(
            TokenizedStrategy.management(),
            token.balanceOf(address(this))
        );
    }
}

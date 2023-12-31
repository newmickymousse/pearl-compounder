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
import {ICurvePool} from "./interfaces/Curve/ICurvePool.sol";

contract PearlLPCompounder is BaseHealthCheck, CustomStrategyTriggerBase {
    using SafeERC20 for ERC20;

    IUSDRExchange private constant USDR_EXCHANGE =
        IUSDRExchange(0x195F7B233947d51F4C3b756ad41a5Ddb34cEBCe0);
    IPearlRouter private constant PEARL_ROUTER =
        IPearlRouter(0xcC25C0FD84737F44a7d38649b69491BBf0c7f083); // use value from: https://docs.pearl.exchange/protocol-details/contract-addresses-v1.5
    IStableSwapPool private constant SYNAPSE_STABLE_POOL =
        IStableSwapPool(0x85fCD7Dd0a1e1A9FCD5FD886ED522dE8221C3EE5);
    ICurvePool private constant CURVE_AAVE_POOL =
        ICurvePool(0x445FE580eF8d70FF569aB36e80c647af338db351);

    ERC20 private constant USDR =
        ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);
    ERC20 private constant PEARL =
        ERC20(0x7238390d5f6F64e67c3211C343A410E2A3DEc142);
    ERC20 private constant DAI =
        ERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);

    address private constant GOV = 0xC4ad0000E223E398DC329235e6C497Db5470B626; //yearn governance on polygon
    uint256 private constant USDR_TO_DAI_PRECISION = 1e9;
    int128 private constant CURVE_DAI_INDEX = 0;
    int128 private constant UNSUPPORTED = -99;

    IRewardPool private immutable pearlRewards;
    IPair private immutable lpToken;
    bool private immutable isStable;

    uint256 public keepPEARL; // 0 is default. the percentage of PEARL we re-lock for boost (in basis points)
    /// @notice Value in PEARL
    uint256 public minRewardsToSell = 3e18; // ~ $1
    /// @notice Max amount of PEARL to sell in single swap
    uint256 public maxRewardsToSell = 1e20; // ~ $33
    /// @notice Value in USDR
    uint256 public minFeesToClaim = 1e9; // ~ $1
    /// @notice Value in BPS
    uint256 public slippageStable = 50; // 0.5% slippage in BPS
    /// @notice The difference to favor token1 compared to token0 when swapping and adding liquidity, 10_000 is equal to both tokens
    uint256 public swapTokenRatio = 10_000;
    /// @notice The address to keep pearl.
    address public keepPearlAddress;
    bool public useCurveStable; // if true, use Curve AAVE pool for stable swaps, default synapse
    int128 public curveStableIndex = UNSUPPORTED; // index of lp token in Curve AAVE pool

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
        uint256 pearlAllowance = PEARL.allowance(
            address(this),
            address(PEARL_ROUTER)
        );
        if (pearlAllowance == 0) {
            PEARL.safeApprove(address(PEARL_ROUTER), type(uint256).max);
        }
        USDR.safeApprove(address(USDR_EXCHANGE), type(uint256).max);

        isStable = lpToken.stable();
        if (isStable) {
            // approve curve pool for stables only
            address usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
            address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
            address dai = address(DAI);
            if (lpToken.token0() == usdc || lpToken.token1() == usdc) {
                ERC20(address(DAI)).safeApprove(
                    address(CURVE_AAVE_POOL),
                    type(uint256).max
                );
                curveStableIndex = 1; // usdc index
            } else if (lpToken.token0() == usdt || lpToken.token1() == usdt) {
                ERC20(address(DAI)).safeApprove(
                    address(CURVE_AAVE_POOL),
                    type(uint256).max
                );
                curveStableIndex = 2; // usdt index
            } else if (lpToken.token0() == dai || lpToken.token1() == dai) {
                // cannot use curve for DAI because DAI is the base token in stable
                // index is used to indicate that it is 3pool token
                curveStableIndex = CURVE_DAI_INDEX; // dai index
            }

            if (curveStableIndex != UNSUPPORTED) {
                // approve synapse pool for 3pool stables only
                DAI.safeApprove(
                    address(SYNAPSE_STABLE_POOL),
                    type(uint256).max
                );
            }
        }
    }

    /// @notice Set the amount and address of PEARL to be kept
    /// @dev cannot set if the address is zero
    /// @param _keepPEARL amount of PEARL to be locked
    function setKeepPEARL(uint256 _keepPEARL) external onlyManagement {
        require(_keepPEARL < MAX_BPS, "!keepPEARL");
        require(keepPearlAddress != address(0), "!keepPearlAddress");
        keepPEARL = _keepPEARL;
    }

    /// @notice Set the address to keep PEARL
    /// @dev cannot be zero address
    /// @param _keepPearlAddress address to keep PEARL
    function setKeepPEARLAddress(
        address _keepPearlAddress
    ) external onlyManagement {
        require(_keepPearlAddress != address(0), "!keepPearlAddress");
        keepPearlAddress = _keepPearlAddress;
    }

    /// @notice Set the amount of PEARL to be sold for asset from each harvest
    /// @dev cannot be more than maxRewardsToSell
    /// @param _minRewardsToSell amount of PEARL to be sold for asset from each harvest
    function setMinRewardsToSell(
        uint256 _minRewardsToSell
    ) external onlyManagement {
        require(_minRewardsToSell < maxRewardsToSell, "!minRewardsToSell");
        minRewardsToSell = _minRewardsToSell;
    }

    /// @notice Set the max amount of PEARL to sell in a single swap
    /// @param _maxRewardsToSell max amount of PEARL to be sold
    function setMaxRewardsToSell(
        uint256 _maxRewardsToSell
    ) external onlyManagement {
        require(_maxRewardsToSell > minRewardsToSell, "!maxRewardsToSell");
        maxRewardsToSell = _maxRewardsToSell;
    }

    /// @notice Set the amount of mint fees to be claimed
    /// @param _minFeesToClaim amount of mint fees to be claimed
    function setMinFeesToClaim(
        uint256 _minFeesToClaim
    ) external onlyManagement {
        minFeesToClaim = _minFeesToClaim;
    }

    /// @notice Set slippage for swapping stable to stable
    /// @param _slippageStable slippage in BPS
    function setSlippageStable(
        uint256 _slippageStable
    ) external onlyManagement {
        require(_slippageStable < MAX_BPS, "!slippageStable");
        slippageStable = _slippageStable;
    }

    /// @notice Set the ratio of token1 to token0 when adding liquidity
    /// @dev If one token is PEARL, the ratio will probably work in different order,
    /// depending on the PEARL position. See function `_claimAndSellRewards()` for details.
    /// @param _swapTokenRatio value in BPS, 10_000 is equal to both tokens.
    /// 11_000 is 10% more token1 than token0 from ideal ratio.
    /// 9_000 is 10% more token0. The value must be below 20_000 and above 0.
    function setSwapTokenRatio(
        uint256 _swapTokenRatio
    ) external onlyManagement {
        require(_swapTokenRatio < 2 * MAX_BPS, "!swapTokenRatio");
        require(_swapTokenRatio > 0, "!swapTokenRatio");
        swapTokenRatio = _swapTokenRatio;
    }

    /// @notice Set if we should use Curve AAVE pool for stable swaps
    /// @dev can use only for USDC and USDT
    /// @param _useCurveStable true if we should use Curve AAVE pool for stable swaps
    function setUseCurveStable(bool _useCurveStable) external onlyManagement {
        require(
            curveStableIndex != UNSUPPORTED &&
                curveStableIndex != CURVE_DAI_INDEX,
            "!curveUnsupported"
        );
        useCurveStable = _useCurveStable;
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

    /// @notice Get value of LP fees in DAI
    /// @return value of LP fees in DAI
    function getClaimableFeesValue() external view returns (uint256) {
        uint256 fees = _getClaimableFees();
        IPearlRouter.route[] memory routes = new IPearlRouter.route[](1);
        routes[0] = IPearlRouter.route(address(USDR), address(DAI), true);
        uint256[] memory amounts = PEARL_ROUTER.getAmountsOut(fees, routes);
        return amounts[1]; // 2 amounts, use the last one
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
            if (
                pearlRewards.earned(address(this)) + balanceOfRewards() >
                minRewardsToSell ||
                _getClaimableFees() > minFeesToClaim
            ) {
                _claimAndSellRewards();
                lpToken.claimFees();
            }

            // add liquidity earned from fees and rewards
            _addLiquidity();

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
     * @dev Check if the strategy is not shutdown and if there are any rewards to be claimed.
     * @return . Should return true if report() should be called by keeper or false if not.
     */
    function reportTrigger(
        address /*_strategy*/
    ) external view override returns (bool, bytes memory) {
        if (TokenizedStrategy.isShutdown()) return (false, bytes("Shutdown"));
        // gas cost is not concern here
        // check if there are any rewards or fees to be claimed
        if (
            pearlRewards.earned(address(this)) + balanceOfRewards() >
            minRewardsToSell ||
            _getClaimableFees() > minFeesToClaim
        ) {
            return (
                true,
                abi.encodeWithSelector(TokenizedStrategy.report.selector)
            );
        }

        return (false, bytes(""));
    }

    /// @dev claimable values are update on each deposit/mint and withdraw/burn of lp tokens
    function _getClaimableFees() internal view returns (uint256 claimable) {
        claimable = _getValueInUSDR(
            lpToken.token0(),
            lpToken.claimable0(address(this))
        );
        claimable += _getValueInUSDR(
            lpToken.token1(),
            lpToken.claimable1(address(this))
        );
    }

    function _getValueInUSDR(
        address _token,
        uint256 _amount
    ) internal view returns (uint256 amountInUsdr) {
        if (_token == address(USDR)) {
            return _amount;
        }
        if (_amount > 0) {
            (amountInUsdr, ) = PEARL_ROUTER.getAmountOut(
                _amount,
                _token,
                address(USDR)
            );
        }
    }

    function _swapUSDRForToken(
        uint256 _usdrAmount,
        address _tokenOut
    ) internal returns (uint256 amountOut) {
        if (_tokenOut != address(USDR)) {
            //if we need anything but USDR, let's withdraw from tangible or sell on pearl to get DAI first
            if (isStable && curveStableIndex != UNSUPPORTED) {
                amountOut = _swapStable(_tokenOut, _usdrAmount);
            } else {
                // this amount is already below maxRewardsToSell, no need to scale down
                amountOut = PEARL_ROUTER.swapExactTokensForTokensSimple(
                    _usdrAmount,
                    0,
                    address(USDR),
                    _tokenOut,
                    isStable, // can be stable for non 3pool tokens
                    address(this),
                    block.timestamp
                )[1];
            }
        }
    }

    function _swapStable(
        address _tokenOut,
        uint256 _usdrAmount
    ) internal returns (uint256 amountOut) {
        amountOut = _swapUsdrToDai(_usdrAmount);

        if (_tokenOut != address(DAI)) {
            uint256 minAmountOut = (amountOut * (MAX_BPS - slippageStable)) /
                MAX_BPS;
            // remove decimals if needed
            uint256 tokenOutDecimals = ERC20(_tokenOut).decimals();
            if (tokenOutDecimals < 18) {
                minAmountOut = minAmountOut / 10 ** (18 - tokenOutDecimals);
            }

            if (useCurveStable) {
                amountOut = CURVE_AAVE_POOL.exchange_underlying(
                    CURVE_DAI_INDEX,
                    curveStableIndex,
                    amountOut,
                    minAmountOut
                );
            } else {
                uint8 daiId = SYNAPSE_STABLE_POOL.getTokenIndex(address(DAI));
                uint8 tokenOutId = SYNAPSE_STABLE_POOL.getTokenIndex(_tokenOut);

                amountOut = SYNAPSE_STABLE_POOL.swap(
                    daiId,
                    tokenOutId,
                    amountOut,
                    minAmountOut,
                    block.timestamp
                );
            }
        }
    }

    /// @dev swap USDR to DAI using PEARL router or redeem from tangible
    function _swapUsdrToDai(uint256 _usdrAmount) internal returns (uint256) {
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
        address tokenA = lpToken.token0();
        address tokenB = lpToken.token1();
        address pearl = address(PEARL);

        uint256 pearlBalance = _claimRewards();
        if (tokenA == pearl || tokenB == pearl) {
            address swapForToken = tokenA == pearl ? tokenB : tokenA;
            _handlePearlAsset(pearlBalance, swapForToken);
            return;
        }

        // swap only maxRewardsToSell to minimize loss
        if (pearlBalance > maxRewardsToSell) {
            pearlBalance = maxRewardsToSell;
        }
        uint256 usdrBalance = PEARL_ROUTER.swapExactTokensForTokensSimple(
            pearlBalance,
            0, // there is no oracle for PEARL, use min amount 0
            address(PEARL),
            address(USDR),
            false, // pearl is not stable
            address(this),
            block.timestamp
        )[1];

        // swap only half of the rewards to other token
        uint256 ratio;
        if (isStable) {
            ratio = _quoteStableLiquidityRatio(tokenA, tokenB);
        } else {
            ratio = 5e17; // 50% ratio
        }
        // ratio is in 1e18, swapTokenRatio is in 1e4
        uint256 usdrToTokenB = (usdrBalance * ratio * swapTokenRatio) /
            1e18 /
            MAX_BPS;
        _swapUSDRForToken(usdrToTokenB, tokenB);
        _swapUSDRForToken(usdrBalance - usdrToTokenB, tokenA);
    }

    /// @dev swap half of pearl rewards to other token. Used only if one of LP tokens is PEARL.
    function _handlePearlAsset(uint256 _amount, address swapForToken) internal {
        // pear is volatiale, swap half amount
        // swapTokenRatio can be in favor of token0 or token1, depending on the order
        // swapTokenRatio will probably work in different order, depending on the PEARL position.
        _amount = (_amount * swapTokenRatio) / MAX_BPS / 2;
        if (_amount > maxRewardsToSell) {
            _amount = maxRewardsToSell;
        }
        PEARL_ROUTER.swapExactTokensForTokensSimple(
            _amount,
            0, // there is no oracle for PEARL, use min amount 0
            address(PEARL),
            swapForToken,
            false, // pearl is not stable
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity() internal {
        address tokenA = lpToken.token0();
        address tokenB = lpToken.token1();

        uint256 amountA = ERC20(tokenA).balanceOf(address(this));
        uint256 amountB = ERC20(tokenB).balanceOf(address(this));

        if (amountA > 0 && amountB > 0) {
            PEARL_ROUTER.addLiquidity(
                tokenA,
                tokenB,
                isStable,
                amountA,
                amountB,
                1,
                1,
                address(this),
                block.timestamp
            );
        }
    }

    function _quoteStableLiquidityRatio(
        address tokenA,
        address tokenB
    ) internal view returns (uint256 ratio) {
        uint256 decimalsA = 10 ** ERC20(tokenA).decimals();
        uint256 decimalsB = 10 ** ERC20(tokenB).decimals();

        uint256 investment = decimalsA;
        uint256 out = lpToken.getAmountOut(investment, tokenA);
        (uint256 amountA, uint256 amountB, ) = PEARL_ROUTER.quoteAddLiquidity(
            tokenA,
            tokenB,
            true,
            investment,
            out
        );

        amountA = (amountA * 1e18) / decimalsA;
        amountB = (amountB * 1e18) / decimalsB;
        out = (out * 1e18) / decimalsB;
        investment = (investment * 1e18) / decimalsA;

        // slither-disable-next-line divide-before-multiply
        ratio = (((out * 1e18) / investment) * amountA) / amountB;
        // slither-disable-next-line divide-before-multiply
        return (investment * 1e18) / (ratio + 1e18);
    }

    function _claimRewards() internal returns (uint256) {
        uint256 pearlBalanceBefore = PEARL.balanceOf(address(this));
        pearlRewards.getReward();
        uint256 pearlBalance = PEARL.balanceOf(address(this));

        if (keepPEARL > 0 && pearlBalance - pearlBalanceBefore > 0) {
            PEARL.safeTransfer(
                keepPearlAddress,
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
        token.safeTransfer(GOV, token.balanceOf(address(this)));
    }
}

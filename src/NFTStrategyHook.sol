// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IStrategyVault} from "src/interfaces/IStrategyVault.sol";

/**
 * @title NFTStrategyHook
 * @notice Uniswap v4 hook that captures a deterministic share of swap flow and routes it to StrategyVault.
 * @custom:security-contact security@nftstrategy.local
 */
contract NFTStrategyHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeCast for int256;

    error NFTStrategyHook__InvalidRevenueShare();
    error NFTStrategyHook__InvalidRevenueToken();
    error NFTStrategyHook__InvalidValuationMode();

    uint16 public constant MAX_BPS = 10_000;
    uint16 public constant MAX_REVENUE_BPS = 2_000;

    struct PoolRevenueConfig {
        bool enabled;
        address revenueToken;
        uint16 revenueShareBps;
        uint128 acquireThreshold;
        uint8 valuationMode;
        uint64 policyNonce;
    }

    mapping(PoolId poolId => PoolRevenueConfig config) public poolRevenueConfig;

    IStrategyVault public immutable strategyVault;

    event ConfigSet(PoolId indexed poolId, bytes32 indexed configHash, uint64 policyNonce);
    event RevenueCaptured(PoolId indexed poolId, uint256 amount, address token);

    constructor(IPoolManager poolManager_, IStrategyVault strategyVault_, address initialOwner)
        BaseHook(poolManager_)
        Ownable(initialOwner)
    {
        strategyVault = strategyVault_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function setPoolRevenueConfig(PoolKey calldata key, PoolRevenueConfig calldata config) external onlyOwner {
        if (config.revenueShareBps > MAX_REVENUE_BPS) {
            revert NFTStrategyHook__InvalidRevenueShare();
        }
        if (config.enabled && config.revenueToken == address(0)) {
            revert NFTStrategyHook__InvalidRevenueToken();
        }
        if (config.valuationMode > 1) {
            revert NFTStrategyHook__InvalidValuationMode();
        }

        PoolId poolId = key.toId();
        poolRevenueConfig[poolId] = config;

        bytes32 configHash = keccak256(
            abi.encode(
                config.enabled,
                config.revenueToken,
                config.revenueShareBps,
                config.acquireThreshold,
                config.valuationMode,
                config.policyNonce
            )
        );

        emit ConfigSet(poolId, configHash, config.policyNonce);
    }

    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        PoolRevenueConfig memory config = poolRevenueConfig[poolId];

        if (!config.enabled) {
            return (BaseHook.afterSwap.selector, 0);
        }

        (Currency unspecifiedCurrency, int128 unspecifiedAmount) = (params.amountSpecified < 0 == params.zeroForOne)
            ? (key.currency1, delta.amount1())
            : (key.currency0, delta.amount0());

        int256 unsignedUnspecified = unspecifiedAmount;
        if (unsignedUnspecified < 0) {
            unsignedUnspecified = -unsignedUnspecified;
        }

        if (Currency.unwrap(unspecifiedCurrency) != config.revenueToken || unsignedUnspecified == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 grossUnspecified = uint256(unsignedUnspecified);
        uint256 feeAmount = (grossUnspecified * config.revenueShareBps) / MAX_BPS;

        if (feeAmount == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        unspecifiedCurrency.take(poolManager, address(strategyVault), feeAmount.toUint128(), false);

        strategyVault.captureRevenue(
            PoolId.unwrap(poolId),
            config.revenueToken,
            feeAmount,
            config.acquireThreshold,
            config.valuationMode,
            config.policyNonce
        );

        emit RevenueCaptured(poolId, feeAmount, config.revenueToken);

        return (BaseHook.afterSwap.selector, feeAmount.toInt256().toInt128());
    }
}

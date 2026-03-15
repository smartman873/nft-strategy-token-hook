// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {MockNFTMarket} from "src/mocks/MockNFTMarket.sol";
import {NFTStrategyHook} from "src/NFTStrategyHook.sol";
import {EasyPosm} from "test/utils/libraries/EasyPosm.sol";
import {BaseTest} from "test/utils/BaseTest.sol";

contract NFTStrategyHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Currency internal currency0;
    Currency internal currency1;

    PoolKey internal poolKey;
    PoolId internal poolId;

    FeeRouter internal feeRouter;
    NFTTreasury internal nftTreasury;
    MockNFTMarket internal mockMarket;
    StrategyVault internal strategyVault;
    NFTStrategyHook internal hook;

    uint256 internal tokenId;
    int24 internal tickLower;
    int24 internal tickUpper;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        feeRouter = new FeeRouter(address(this));
        nftTreasury = new NFTTreasury(address(this));
        mockMarket = new MockNFTMarket(IERC20(Currency.unwrap(currency1)), 1e16, 1e15, 50, address(this));
        strategyVault =
            new StrategyVault(IERC20(Currency.unwrap(currency1)), feeRouter, nftTreasury, mockMarket, address(this));

        // Deploy hook to a valid flag address.
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)
                ^ (0x4444 << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager, strategyVault, address(this));
        deployCodeTo("NFTStrategyHook.sol:NFTStrategyHook", constructorArgs, flags);
        hook = NFTStrategyHook(flags);

        strategyVault.setHook(address(hook));
        nftTreasury.setVault(address(strategyVault));

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();

        feeRouter.setPoolSplit(PoolId.unwrap(poolId), 10_000, 0, address(0));

        hook.setPoolRevenueConfig(
            poolKey,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: Currency.unwrap(currency1),
                revenueShareBps: 500,
                acquireThreshold: 1e16,
                valuationMode: 0,
                policyNonce: 1
            })
        );

        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function test_CapturesRevenueAfterSwap() external {
        uint256 beforeBalance = IERC20(Currency.unwrap(currency1)).balanceOf(address(strategyVault));

        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        uint256 afterBalance = IERC20(Currency.unwrap(currency1)).balanceOf(address(strategyVault));
        (,,, uint256 reserve,) = strategyVault.poolPolicies(PoolId.unwrap(poolId));

        assertGt(afterBalance, beforeBalance);
        assertGt(reserve, 0);
    }

    function test_CanAcquireNftAfterRevenueThreshold() external {
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        strategyVault.acquireNFT(PoolId.unwrap(poolId), type(uint256).max);

        assertEq(nftTreasury.inventoryCount(PoolId.unwrap(poolId)), 1);
    }

    function test_RevertWhen_HookFlagsMismatch() external {
        address invalidFlags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x5555 << 144));
        bytes memory constructorArgs = abi.encode(poolManager, strategyVault, address(this));

        vm.expectRevert();
        deployCodeTo("NFTStrategyHook.sol:NFTStrategyHook", constructorArgs, invalidFlags);
    }
}

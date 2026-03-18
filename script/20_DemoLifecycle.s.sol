// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

import {FeeRouter} from "src/FeeRouter.sol";
import {NFTStrategyHook} from "src/NFTStrategyHook.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {StrategyShareToken} from "src/StrategyShareToken.sol";

contract DemoLifecycleScript is Script {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant STARTING_PRICE = 2 ** 96;
    uint24 internal constant LP_FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    uint256 internal constant OWNER_MINT = 200_000e18;
    uint256 internal constant USER_MINT = 50_000e18;
    uint128 internal constant LIQUIDITY_AMOUNT = 100e18;
    uint256 internal constant DEPOSIT_ASSETS = 20e18;
    uint256 internal constant SWAP_AMOUNT = 10e18;

    uint16 internal constant TREASURY_BPS = 1000;
    uint16 internal constant STRATEGY_BPS = 9000;
    uint16 internal constant REVENUE_BPS = 500;

    uint128 internal constant ACQUIRE_THRESHOLD = 3e16;
    uint8 internal constant VALUATION_MODE = 0;
    uint64 internal constant POLICY_NONCE = 1;

    address internal constant UNICHAIN_V4_ROUTER = 0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba;
    address internal constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 internal ownerPrivateKey;
    uint256 internal userPrivateKey;
    address internal owner;
    address internal user;

    IPoolManager internal poolManager;
    IPositionManager internal positionManager;
    IUniswapV4Router04 internal swapRouter;
    IPermit2 internal permit2;

    MockERC20 internal token0;
    MockERC20 internal token1;

    FeeRouter internal feeRouter;
    NFTStrategyHook internal hook;
    StrategyVault internal vault;
    NFTTreasury internal treasury;

    PoolKey internal poolKey;
    bytes32 internal poolIdRaw;

    struct UserMetrics {
        uint256 userAssetBefore;
        uint256 userAssetAfter;
        uint256 userSharesBefore;
        uint256 userSharesAfter;
        uint256 mintedShares;
        uint256 reserveBeforeAcquire;
        uint256 reserveAfterAcquire;
        uint256 acquiredTokenId;
        uint256 acquireCost;
        uint256 inventoryCount;
        uint256 nftCount;
    }

    function run() external {
        _loadContext();

        uint256 lpTokenId = _ownerPhase();
        UserMetrics memory metrics = _userPhase();

        _printSummary(metrics, lpTokenId);

        _envLogAddress("DEMO_USER_ADDRESS", user);
        _envLogBytes32("DEMO_POOL_ID", poolIdRaw);
        _envLogUint("DEMO_LP_POSITION_TOKEN_ID", lpTokenId);
        _envLogAddress("V4_SWAP_ROUTER_ADDRESS", address(swapRouter));
    }

    function _loadContext() internal {
        ownerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        owner = vm.addr(ownerPrivateKey);

        address ownerFromEnv = vm.envOr("OWNER_ADDRESS", owner);
        require(owner == ownerFromEnv, "DemoLifecycle: owner mismatch");

        userPrivateKey = vm.envOr("DEMO_USER_PRIVATE_KEY", uint256(0xA11CE));
        user = vm.addr(userPrivateKey);

        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER_ADDRESS"));

        address routerAddress = vm.envOr("V4_SWAP_ROUTER_ADDRESS", UNICHAIN_V4_ROUTER);
        swapRouter = IUniswapV4Router04(payable(routerAddress));
        permit2 = IPermit2(vm.envOr("PERMIT2_ADDRESS", PERMIT2_ADDRESS));

        token0 = MockERC20(vm.envAddress("DEMO_TOKEN0_ADDRESS"));
        token1 = MockERC20(vm.envAddress("DEMO_TOKEN1_ADDRESS"));
        require(address(token0) < address(token1), "DemoLifecycle: token order");

        feeRouter = FeeRouter(vm.envAddress("FEE_ROUTER_ADDRESS"));
        hook = NFTStrategyHook(vm.envAddress("NFT_STRATEGY_HOOK_ADDRESS"));
        vault = StrategyVault(vm.envAddress("STRATEGY_VAULT_ADDRESS"));
        treasury = NFTTreasury(vm.envAddress("NFT_TREASURY_ADDRESS"));

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        poolIdRaw = PoolId.unwrap(poolKey.toId());
    }

    function _ownerPhase() internal returns (uint256 lpTokenId) {
        console2.log("phase: owner setup + pool init + liquidity");
        bool shouldInitialize = _poolNeedsInitialization();

        vm.startBroadcast(ownerPrivateKey);

        if (user.balance < 0.005 ether) {
            payable(user).transfer(0.02 ether);
        }

        token0.mint(owner, OWNER_MINT);
        token1.mint(owner, OWNER_MINT);
        token0.mint(user, USER_MINT);
        token1.mint(user, USER_MINT);

        _approveForV4(token0);
        _approveForV4(token1);

        feeRouter.setPoolSplit(poolIdRaw, STRATEGY_BPS, TREASURY_BPS, owner);

        hook.setPoolRevenueConfig(
            poolKey,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: address(token1),
                revenueShareBps: REVENUE_BPS,
                acquireThreshold: ACQUIRE_THRESHOLD,
                valuationMode: VALUATION_MODE,
                policyNonce: POLICY_NONCE
            })
        );

        if (shouldInitialize) {
            poolManager.initialize(poolKey, STARTING_PRICE);
        }

        int24 tickLower = TickMath.minUsableTick(TICK_SPACING);
        int24 tickUpper = TickMath.maxUsableTick(TICK_SPACING);
        // Rerun-safe max bounds: pool price may have moved from STARTING_PRICE.
        lpTokenId = _mintPosition(tickLower, tickUpper, LIQUIDITY_AMOUNT, type(uint128).max, type(uint128).max, owner);

        vm.stopBroadcast();
    }

    function _poolNeedsInitialization() internal view returns (bool) {
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolKey.toId());
        return sqrtPriceX96 == 0;
    }

    function _userPhase() internal returns (UserMetrics memory metrics) {
        console2.log("phase: user deposit + swaps + acquire + redeem");

        vm.startBroadcast(userPrivateKey);

        _approveForV4(token0);
        _approveForV4(token1);
        token1.approve(address(vault), type(uint256).max);

        StrategyShareToken share = StrategyShareToken(vault.shareToken());

        metrics.userAssetBefore = token1.balanceOf(user);
        metrics.userSharesBefore = share.balanceOf(user);

        metrics.mintedShares = vault.deposit(DEPOSIT_ASSETS, user, 0);

        swapRouter.swapExactTokensForTokens({
            amountIn: SWAP_AMOUNT,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: bytes(""),
            receiver: user,
            deadline: block.timestamp + 20 minutes
        });

        swapRouter.swapExactTokensForTokens({
            amountIn: SWAP_AMOUNT,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: bytes(""),
            receiver: user,
            deadline: block.timestamp + 20 minutes
        });

        (,,, metrics.reserveBeforeAcquire,) = vault.poolPolicies(poolIdRaw);
        (metrics.acquiredTokenId, metrics.acquireCost) = vault.acquireNFT(poolIdRaw, type(uint256).max);

        uint256 userSharesAfterMint = share.balanceOf(user);
        uint256 redeemShares = userSharesAfterMint / 2;
        if (redeemShares > 0) {
            vault.redeem(redeemShares, user, 0);
        }

        vm.stopBroadcast();

        (,,, metrics.reserveAfterAcquire, metrics.nftCount) = vault.poolPolicies(poolIdRaw);
        metrics.inventoryCount = treasury.inventoryCount(poolIdRaw);
        metrics.userAssetAfter = token1.balanceOf(user);
        metrics.userSharesAfter = share.balanceOf(user);
    }

    function _approveForV4(MockERC20 token) internal {
        token.approve(address(permit2), type(uint256).max);
        token.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(token), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token), address(poolManager), type(uint160).max, type(uint48).max);
    }

    function _mintPosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityAmount,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient
    ) internal returns (uint256 tokenId) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidityAmount, amount0Max, amount1Max, recipient, bytes(""));
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, recipient);
        params[3] = abi.encode(poolKey.currency1, recipient);

        tokenId = positionManager.nextTokenId();
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 30 minutes);
    }

    function _printSummary(UserMetrics memory metrics, uint256 lpTokenId) internal pure {
        console2.log("metric:userAssetBefore", metrics.userAssetBefore);
        console2.log("metric:userAssetAfter", metrics.userAssetAfter);
        console2.log("metric:userSharesBefore", metrics.userSharesBefore);
        console2.log("metric:mintedShares", metrics.mintedShares);
        console2.log("metric:userSharesAfter", metrics.userSharesAfter);

        console2.log("metric:reserveBeforeAcquire", metrics.reserveBeforeAcquire);
        console2.log("metric:reserveAfterAcquire", metrics.reserveAfterAcquire);
        console2.log("metric:nftCountPolicy", metrics.nftCount);
        console2.log("metric:inventoryCount", metrics.inventoryCount);
        console2.log("metric:acquiredTokenId", metrics.acquiredTokenId);
        console2.log("metric:acquireCost", metrics.acquireCost);
        console2.log("metric:lpTokenId", lpTokenId);
    }

    function _envLogAddress(string memory key, address value) internal view {
        console2.log(string.concat("ENV:", key, "=", vm.toString(value)));
    }

    function _envLogBytes32(string memory key, bytes32 value) internal view {
        console2.log(string.concat("ENV:", key, "=", vm.toString(value)));
    }

    function _envLogUint(string memory key, uint256 value) internal view {
        console2.log(string.concat("ENV:", key, "=", vm.toString(value)));
    }
}

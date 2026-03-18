// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {FeeRouter} from "src/FeeRouter.sol";
import {NFTStrategyHook} from "src/NFTStrategyHook.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyShareToken} from "src/StrategyShareToken.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {IStrategyVault} from "src/interfaces/IStrategyVault.sol";
import {MockNFTMarket} from "src/mocks/MockNFTMarket.sol";
import {MockStrategyNFT} from "src/mocks/MockStrategyNFT.sol";

contract MintableNFT is ERC721 {
    constructor() ERC721("Mintable", "MNT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract BadFeeRouter {
    function route(bytes32, uint256 amount) external pure returns (uint256, uint256, address) {
        return (amount, 1, address(0));
    }
}

contract DummyPoolManager {
    function take(Currency, address, uint256) external {}

    function mint(address, uint256, uint256) external {}
}

contract DummyStrategyVault is IStrategyVault {
    uint256 public lastCapturedAmount;

    function captureRevenue(bytes32, address, uint256 amount, uint128, uint8, uint64) external override {
        lastCapturedAmount = amount;
    }
}

contract BranchCoverageTest is Test {
    using PoolIdLibrary for PoolKey;

    bytes32 internal constant POOL_A = keccak256("POOL_A");

    MockERC20 internal asset;
    FeeRouter internal feeRouter;
    NFTTreasury internal treasury;
    MockNFTMarket internal market;
    StrategyVault internal vault;

    function setUp() public {
        asset = new MockERC20("Asset", "AST", 18);
        feeRouter = new FeeRouter(address(this));
        treasury = new NFTTreasury(address(this));
        market = new MockNFTMarket(IERC20(address(asset)), 1e18, 1e17, 5, address(this));
        vault = new StrategyVault(IERC20(address(asset)), feeRouter, treasury, market, address(this));

        treasury.setVault(address(vault));
        vault.setHook(address(this));

        asset.mint(address(this), 1_000_000e18);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(market), type(uint256).max);
    }

    function test_FeeRouterBranchesAndRoutes() external {
        bytes32 poolId = POOL_A;

        vm.expectRevert(FeeRouter.FeeRouter__InvalidSplit.selector);
        feeRouter.setPoolSplit(poolId, 100, 100, address(0));

        vm.expectRevert(FeeRouter.FeeRouter__TreasuryRequired.selector);
        feeRouter.setPoolSplit(poolId, 9000, 1000, address(0));

        (uint256 s0, uint256 t0, address r0) = feeRouter.route(poolId, 123);
        assertEq(s0, 123);
        assertEq(t0, 0);
        assertEq(r0, address(0));

        feeRouter.setPoolSplit(poolId, 8500, 1500, address(0xCAFE));

        (uint256 s1, uint256 t1, address r1) = feeRouter.quoteRoute(poolId, 2000);
        assertEq(s1, 1700);
        assertEq(t1, 300);
        assertEq(r1, address(0xCAFE));
    }

    function test_StrategyShareTokenBranches() external {
        vm.expectRevert(StrategyShareToken.StrategyShareToken__ZeroVault.selector);
        new StrategyShareToken(address(0));

        StrategyShareToken share = new StrategyShareToken(address(this));

        vm.prank(address(0xBEEF));
        vm.expectRevert(StrategyShareToken.StrategyShareToken__OnlyVault.selector);
        share.mint(address(this), 1);

        vm.prank(address(0xBEEF));
        vm.expectRevert(StrategyShareToken.StrategyShareToken__OnlyVault.selector);
        share.burn(address(this), 1);

        share.mint(address(this), 10);
        assertEq(share.totalSupply(), 10);
        share.burn(address(this), 3);
        assertEq(share.totalSupply(), 7);
    }

    function test_NFTTreasuryBranchesAndSweep() external {
        MintableNFT nft = new MintableNFT();

        vm.expectRevert(NFTTreasury.NFTTreasury__ZeroVault.selector);
        treasury.setVault(address(0));

        vm.prank(address(0xBEEF));
        vm.expectRevert(NFTTreasury.NFTTreasury__OnlyVault.selector);
        treasury.recordAcquisition(POOL_A, address(nft), 1, 1e18);

        nft.mint(address(treasury), 1);
        vm.prank(address(vault));
        treasury.recordAcquisition(POOL_A, address(nft), 1, 1e18);

        assertEq(treasury.inventoryCount(POOL_A), 1);
        NFTTreasury.InventoryItem[] memory items = treasury.inventoryForPool(POOL_A);
        assertEq(items.length, 1);
        assertEq(items[0].tokenId, 1);
        uint256[] memory ids = treasury.tokenIdsForCollection(address(nft));
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);

        address recipient = makeAddr("sweepRecipient");
        treasury.sweep(address(nft), 1, recipient);
        assertEq(nft.ownerOf(1), recipient);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        treasury.sweep(address(nft), 1, address(0xBEEF));
    }

    function test_MockStrategyNftOnlyMarket() external {
        MockStrategyNFT nft = new MockStrategyNFT(address(this));

        vm.prank(address(0xBEEF));
        vm.expectRevert(MockStrategyNFT.MockStrategyNFT__OnlyMarket.selector);
        nft.mintForMarket(1);

        nft.mintForMarket(1);
        assertEq(nft.ownerOf(1), address(this));
    }

    function test_MockMarketBranches() external {
        vm.expectRevert(MockNFTMarket.MockNFTMarket__ZeroAsset.selector);
        new MockNFTMarket(IERC20(address(0)), 1e18, 0, 1, address(this));

        vm.expectRevert(MockNFTMarket.MockNFTMarket__ZeroMaxSupply.selector);
        new MockNFTMarket(IERC20(address(asset)), 1e18, 0, 0, address(this));

        MockNFTMarket oneItemMarket = new MockNFTMarket(IERC20(address(asset)), 1e18, 0, 1, address(this));
        address recipient = makeAddr("recipient");

        vm.expectRevert(MockNFTMarket.MockNFTMarket__PriceExceedsLimit.selector);
        oneItemMarket.buyNext(recipient, 1e17);

        asset.approve(address(oneItemMarket), type(uint256).max);
        oneItemMarket.buyNext(recipient, type(uint256).max);

        vm.expectRevert(MockNFTMarket.MockNFTMarket__OutOfInventory.selector);
        oneItemMarket.buyNext(recipient, type(uint256).max);

        assertEq(oneItemMarket.floorPrice(), 1e18);
    }

    function test_StrategyVaultErrorBranches() external {
        vm.expectRevert(StrategyVault.StrategyVault__ZeroAddress.selector);
        new StrategyVault(IERC20(address(0)), feeRouter, treasury, market, address(this));

        vm.expectRevert(StrategyVault.StrategyVault__ZeroAddress.selector);
        vault.setHook(address(0));

        vm.expectRevert(StrategyVault.StrategyVault__InvalidAmount.selector);
        vault.deposit(0, address(this), 0);

        vm.expectRevert(StrategyVault.StrategyVault__SlippageExceeded.selector);
        vault.deposit(1e18, address(this), type(uint256).max);

        uint256 shares = vault.deposit(1e18, address(this), 0);
        assertEq(vault.totalManagedAssets(), 1e18);
        assertGt(vault.previewDeposit(1e18), 0);
        assertEq(vault.previewRedeem(shares), 1e18);

        vm.expectRevert(StrategyVault.StrategyVault__InvalidAmount.selector);
        vault.redeem(0, address(this), 0);

        vm.expectRevert(StrategyVault.StrategyVault__SlippageExceeded.selector);
        vault.redeem(shares, address(this), type(uint256).max);

        vault.setHook(address(0x1234));
        vm.expectRevert(StrategyVault.StrategyVault__OnlyHook.selector);
        vault.captureRevenue(POOL_A, address(asset), 1, 1, 0, 1);

        vault.setHook(address(this));

        vm.expectRevert(StrategyVault.StrategyVault__InvalidAmount.selector);
        vault.captureRevenue(POOL_A, address(asset), 0, 1, 0, 1);

        vm.expectRevert(StrategyVault.StrategyVault__InvalidRevenueToken.selector);
        vault.captureRevenue(POOL_A, address(0xBEEF), 1, 1, 0, 1);

        vm.expectRevert(StrategyVault.StrategyVault__InvalidValuationMode.selector);
        vault.captureRevenue(POOL_A, address(asset), 1, 1, 2, 1);

        asset.mint(address(vault), 100e18);
        vault.captureRevenue(POOL_A, address(asset), 100e18, 10e18, 1, 2);

        vm.expectRevert(StrategyVault.StrategyVault__StalePolicyNonce.selector);
        vault.captureRevenue(POOL_A, address(asset), 1e18, 10e18, 1, 1);

        (uint128 threshold, uint8 mode,, uint256 reserve,) = vault.poolPolicies(POOL_A);
        assertEq(threshold, 10e18);
        assertEq(mode, 1);
        assertEq(reserve, 100e18);

        uint256 val = vault.poolValuation(POOL_A);
        assertEq(val, 100e18);

        vm.expectRevert(StrategyVault.StrategyVault__InsufficientRevenueReserve.selector);
        vault.acquireNFT(POOL_A, 1);

        (uint256 tokenId,) = vault.acquireNFT(POOL_A, type(uint256).max);
        assertEq(tokenId, 1);

        uint256 valAfter = vault.poolValuation(POOL_A);
        assertGt(valAfter, 0);

        bytes32 poolB = keccak256("POOL_B");
        asset.mint(address(vault), 1e18);
        vault.captureRevenue(poolB, address(asset), 1e18, 0, 0, 1);
        vm.expectRevert(StrategyVault.StrategyVault__BelowAcquireThreshold.selector);
        vault.acquireNFT(poolB, type(uint256).max);

        BadFeeRouter bad = new BadFeeRouter();
        StrategyVault badVault = new StrategyVault(
            IERC20(address(asset)), FeeRouter(address(bad)), treasury, market, address(this)
        );
        badVault.setHook(address(this));
        asset.mint(address(badVault), 2e18);

        vm.expectRevert(StrategyVault.StrategyVault__AccountingMismatch.selector);
        badVault.captureRevenue(POOL_A, address(asset), 2e18, 1, 0, 1);
    }

    function test_StrategyVaultAcquireReserveBranch() external {
        bytes32 poolId = keccak256("SMALL_RESERVE");
        asset.mint(address(vault), 5e17);
        vault.captureRevenue(poolId, address(asset), 5e17, 1, 0, 1);

        vm.expectRevert(StrategyVault.StrategyVault__InsufficientRevenueReserve.selector);
        vault.acquireNFT(poolId, type(uint256).max);
    }
}

contract HookBranchCoverageTest is Test {
    using PoolIdLibrary for PoolKey;

    NFTStrategyHook internal hook;
    PoolKey internal key;
    DummyPoolManager internal poolManager;
    DummyStrategyVault internal strategyVault;

    function setUp() public {
        poolManager = new DummyPoolManager();
        strategyVault = new DummyStrategyVault();

        address flags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        bytes memory constructorArgs =
            abi.encode(IPoolManager(address(poolManager)), IStrategyVault(address(strategyVault)), address(this));
        deployCodeTo("NFTStrategyHook.sol:NFTStrategyHook", constructorArgs, flags);

        hook = NFTStrategyHook(flags);

        Currency c0 = Currency.wrap(address(0x1111));
        Currency c1 = Currency.wrap(address(0x2222));
        key = PoolKey(c0, c1, 3000, 60, IHooks(hook));
    }

    function test_ConfigValidationBranches() external {
        NFTStrategyHook.PoolRevenueConfig memory cfg = NFTStrategyHook.PoolRevenueConfig({
            enabled: true,
            revenueToken: address(0x2222),
            revenueShareBps: 2001,
            acquireThreshold: 1,
            valuationMode: 0,
            policyNonce: 1
        });

        vm.expectRevert(NFTStrategyHook.NFTStrategyHook__InvalidRevenueShare.selector);
        hook.setPoolRevenueConfig(key, cfg);

        cfg.revenueShareBps = 100;
        cfg.revenueToken = address(0);
        vm.expectRevert(NFTStrategyHook.NFTStrategyHook__InvalidRevenueToken.selector);
        hook.setPoolRevenueConfig(key, cfg);

        cfg.revenueToken = address(0x2222);
        cfg.valuationMode = 2;
        vm.expectRevert(NFTStrategyHook.NFTStrategyHook__InvalidValuationMode.selector);
        hook.setPoolRevenueConfig(key, cfg);

        cfg.valuationMode = 1;
        hook.setPoolRevenueConfig(key, cfg);
    }

    function test_AfterSwapEarlyReturnBranches() external {
        PoolId poolId = key.toId();

        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: 0});

        // disabled config path
        vm.prank(address(0xABCD));
        vm.expectRevert();
        hook.afterSwap(address(this), key, params, toBalanceDelta(0, 1), "");

        // set enabled config
        NFTStrategyHook.PoolRevenueConfig memory cfg = NFTStrategyHook.PoolRevenueConfig({
            enabled: true,
            revenueToken: address(0x1111),
            revenueShareBps: 100,
            acquireThreshold: 1,
            valuationMode: 0,
            policyNonce: 1
        });
        hook.setPoolRevenueConfig(key, cfg);
        (bool enabled,,,,,) = hook.poolRevenueConfig(poolId);
        assertTrue(enabled);
    }

    function test_AfterSwapPathsViaDirectCall() external {
        address poolManagerAddress = address(hook.poolManager());

        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: 0});

        // disabled path
        vm.prank(poolManagerAddress);
        (, int128 fee0) = hook.afterSwap(address(this), key, params, toBalanceDelta(0, 10), "");
        assertEq(fee0, 0);

        // enabled with token mismatch path
        hook.setPoolRevenueConfig(
            key,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: address(0x1111),
                revenueShareBps: 100,
                acquireThreshold: 1,
                valuationMode: 0,
                policyNonce: 2
            })
        );

        vm.prank(poolManagerAddress);
        (, int128 fee1) = hook.afterSwap(address(this), key, params, toBalanceDelta(0, -10), "");
        assertEq(fee1, 0);

        // enabled token match but zero unspecified path
        hook.setPoolRevenueConfig(
            key,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: address(0x2222),
                revenueShareBps: 100,
                acquireThreshold: 1,
                valuationMode: 0,
                policyNonce: 3
            })
        );

        vm.prank(poolManagerAddress);
        (, int128 fee2) = hook.afterSwap(address(this), key, params, toBalanceDelta(0, 0), "");
        assertEq(fee2, 0);

        // feeAmount == 0 path
        hook.setPoolRevenueConfig(
            key,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: address(0x2222),
                revenueShareBps: 1,
                acquireThreshold: 1,
                valuationMode: 0,
                policyNonce: 4
            })
        );

        vm.prank(poolManagerAddress);
        (, int128 fee3) = hook.afterSwap(address(this), key, params, toBalanceDelta(0, 1), "");
        assertEq(fee3, 0);

        // positive fee path with unspecifiedAmount negative branch covered
        hook.setPoolRevenueConfig(
            key,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: address(0x2222),
                revenueShareBps: 500,
                acquireThreshold: 1,
                valuationMode: 0,
                policyNonce: 5
            })
        );

        vm.prank(poolManagerAddress);
        (, int128 fee4) = hook.afterSwap(address(this), key, params, toBalanceDelta(0, -100), "");
        assertEq(fee4, 5);

        // unspecified amount positive branch (amountSpecified > 0 picks amount0 with zeroForOne true)
        SwapParams memory exactOutParams = SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: 0});
        hook.setPoolRevenueConfig(
            key,
            NFTStrategyHook.PoolRevenueConfig({
                enabled: true,
                revenueToken: address(0x1111),
                revenueShareBps: 100,
                acquireThreshold: 1,
                valuationMode: 0,
                policyNonce: 6
            })
        );

        vm.prank(poolManagerAddress);
        (, int128 fee5) = hook.afterSwap(address(this), key, exactOutParams, toBalanceDelta(100, 0), "");
        assertEq(fee5, 1);

        assertEq(strategyVault.lastCapturedAmount(), 1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {MockNFTMarket} from "src/mocks/MockNFTMarket.sol";

contract StrategyVaultTest is Test {
    bytes32 internal constant POOL_ID = keccak256("POOL_A");

    MockERC20 internal asset;
    FeeRouter internal feeRouter;
    NFTTreasury internal treasury;
    MockNFTMarket internal market;
    StrategyVault internal vault;

    address internal treasurySink = makeAddr("treasurySink");

    function setUp() public {
        asset = new MockERC20("Asset", "AST", 18);
        feeRouter = new FeeRouter(address(this));
        treasury = new NFTTreasury(address(this));
        market = new MockNFTMarket(IERC20(address(asset)), 1e18, 1e17, 100, address(this));
        vault = new StrategyVault(IERC20(address(asset)), feeRouter, treasury, market, address(this));

        treasury.setVault(address(vault));
        vault.setHook(address(this));

        feeRouter.setPoolSplit(POOL_ID, 9_000, 1_000, treasurySink);

        asset.mint(address(this), 1_000_000e18);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_DepositAndRedeemRoundTrip() external {
        uint256 depositAmount = 100e18;
        uint256 shares = vault.deposit(depositAmount, address(this), 0);
        uint256 redeemedAssets = vault.redeem(shares, address(this), 0);

        assertGt(shares, 0);
        assertLe(redeemedAssets, depositAmount);
    }

    function test_RevertWhen_UnauthorizedRevenueCapture() external {
        vault.setHook(makeAddr("authorizedHook"));
        vm.expectRevert(StrategyVault.StrategyVault__OnlyHook.selector);
        vault.captureRevenue(POOL_ID, address(asset), 1e18, 1e18, 0, 1);
    }

    function test_CaptureRevenueAndAcquireNft() external {
        uint256 capturedAmount = 100e18;
        asset.mint(address(vault), capturedAmount);

        vault.captureRevenue(POOL_ID, address(asset), capturedAmount, 50e18, 0, 1);

        (,, uint64 policyNonce, uint256 reserve, uint256 nftCount) = vault.poolPolicies(POOL_ID);
        assertEq(policyNonce, 1);
        assertEq(reserve, 90e18);
        assertEq(nftCount, 0);
        assertEq(asset.balanceOf(treasurySink), 10e18);

        (uint256 tokenId, uint256 cost) = vault.acquireNFT(POOL_ID, type(uint256).max);

        (,,,, nftCount) = vault.poolPolicies(POOL_ID);
        assertEq(tokenId, 1);
        assertEq(cost, 1e18);
        assertEq(nftCount, 1);
        assertEq(treasury.inventoryCount(POOL_ID), 1);
    }

    function test_RevertWhen_AcquireBelowThreshold() external {
        uint256 capturedAmount = 10e18;
        asset.mint(address(vault), capturedAmount);

        vault.captureRevenue(POOL_ID, address(asset), capturedAmount, 50e18, 0, 1);

        vm.expectRevert(StrategyVault.StrategyVault__BelowAcquireThreshold.selector);
        vault.acquireNFT(POOL_ID, type(uint256).max);
    }

    function testFuzz_RouteConservesRevenue(uint96 capturedAmount, uint16 treasuryBps) external {
        capturedAmount = uint96(bound(capturedAmount, 1e6, uint96(type(uint128).max)));
        treasuryBps = uint16(bound(treasuryBps, 0, 9_000));

        feeRouter.setPoolSplit(POOL_ID, uint16(10_000 - treasuryBps), treasuryBps, treasurySink);

        uint256 beforeTreasuryBalance = asset.balanceOf(treasurySink);
        asset.mint(address(vault), capturedAmount);

        vault.captureRevenue(POOL_ID, address(asset), capturedAmount, 1, 0, 2);

        (,,, uint256 reserve,) = vault.poolPolicies(POOL_ID);
        uint256 treasuryDelta = asset.balanceOf(treasurySink) - beforeTreasuryBalance;

        assertEq(reserve + treasuryDelta, capturedAmount);
    }
}

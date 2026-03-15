// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyShareToken} from "src/StrategyShareToken.sol";
import {MockNFTMarket} from "src/mocks/MockNFTMarket.sol";

/**
 * @title StrategyVault
 * @notice Revenue vault that mints strategy shares, receives hook revenue, and acquires NFTs deterministically.
 * @custom:security-contact security@nftstrategy.local
 */
contract StrategyVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error StrategyVault__OnlyHook();
    error StrategyVault__ZeroAddress();
    error StrategyVault__InvalidAmount();
    error StrategyVault__SlippageExceeded();
    error StrategyVault__InvalidRevenueToken();
    error StrategyVault__InvalidValuationMode();
    error StrategyVault__StalePolicyNonce();
    error StrategyVault__BelowAcquireThreshold();
    error StrategyVault__InsufficientRevenueReserve();
    error StrategyVault__AccountingMismatch();

    uint256 public constant VIRTUAL_ASSETS = 1e6;
    uint256 public constant VIRTUAL_SHARES = 1e6;

    uint8 public constant VALUATION_ZERO_VALUE = 0;
    uint8 public constant VALUATION_MOCK_FLOOR = 1;

    struct PoolPolicy {
        uint128 acquireThreshold;
        uint8 valuationMode;
        uint64 policyNonce;
        uint256 revenueReserve;
        uint256 nftCount;
    }

    IERC20 public immutable asset;
    FeeRouter public immutable feeRouter;
    NFTTreasury public immutable nftTreasury;
    MockNFTMarket public immutable nftMarket;
    StrategyShareToken public immutable shareToken;

    address public hook;

    mapping(bytes32 poolId => PoolPolicy policy) public poolPolicies;

    event HookSet(address indexed hook);
    event RevenueCaptured(bytes32 indexed poolId, uint256 amount, address token);
    event NFTAcquired(bytes32 indexed poolId, address indexed nftContract, uint256 indexed tokenId, uint256 cost);
    event SharesMinted(address indexed user, uint256 shares, uint256 deposit);
    event SharesBurned(address indexed user, uint256 shares, uint256 withdraw);

    constructor(
        IERC20 asset_,
        FeeRouter feeRouter_,
        NFTTreasury nftTreasury_,
        MockNFTMarket nftMarket_,
        address initialOwner
    ) Ownable(initialOwner) {
        if (
            address(asset_) == address(0) || address(feeRouter_) == address(0) || address(nftTreasury_) == address(0)
                || address(nftMarket_) == address(0)
        ) {
            revert StrategyVault__ZeroAddress();
        }

        asset = asset_;
        feeRouter = feeRouter_;
        nftTreasury = nftTreasury_;
        nftMarket = nftMarket_;
        shareToken = new StrategyShareToken(address(this));
    }

    function setHook(address hook_) external onlyOwner {
        if (hook_ == address(0)) {
            revert StrategyVault__ZeroAddress();
        }
        hook = hook_;
        emit HookSet(hook_);
    }

    function deposit(uint256 assets, address receiver, uint256 minShares)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) {
            revert StrategyVault__InvalidAmount();
        }

        shares = previewDeposit(assets);
        if (shares < minShares || shares == 0) {
            revert StrategyVault__SlippageExceeded();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);
        shareToken.mint(receiver, shares);

        emit SharesMinted(receiver, shares, assets);
    }

    function redeem(uint256 shares, address receiver, uint256 minAssets)
        external
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) {
            revert StrategyVault__InvalidAmount();
        }

        assets = previewRedeem(shares);
        if (assets < minAssets || assets == 0) {
            revert StrategyVault__SlippageExceeded();
        }

        shareToken.burn(msg.sender, shares);
        asset.safeTransfer(receiver, assets);

        emit SharesBurned(msg.sender, shares, assets);
    }

    function captureRevenue(
        bytes32 poolId,
        address token,
        uint256 amount,
        uint128 acquireThreshold,
        uint8 valuationMode,
        uint64 policyNonce
    ) external nonReentrant {
        if (msg.sender != hook) {
            revert StrategyVault__OnlyHook();
        }
        if (amount == 0) {
            revert StrategyVault__InvalidAmount();
        }
        if (token != address(asset)) {
            revert StrategyVault__InvalidRevenueToken();
        }
        if (valuationMode > VALUATION_MOCK_FLOOR) {
            revert StrategyVault__InvalidValuationMode();
        }

        PoolPolicy storage policy = poolPolicies[poolId];
        if (policyNonce < policy.policyNonce) {
            revert StrategyVault__StalePolicyNonce();
        }

        if (policyNonce > policy.policyNonce) {
            policy.acquireThreshold = acquireThreshold;
            policy.valuationMode = valuationMode;
            policy.policyNonce = policyNonce;
        }

        (uint256 strategyAmount, uint256 treasuryAmount, address treasuryRecipient) = feeRouter.route(poolId, amount);

        if (strategyAmount + treasuryAmount != amount) {
            revert StrategyVault__AccountingMismatch();
        }

        if (treasuryAmount > 0) {
            asset.safeTransfer(treasuryRecipient, treasuryAmount);
        }

        policy.revenueReserve += strategyAmount;

        emit RevenueCaptured(poolId, amount, token);
    }

    function acquireNFT(bytes32 poolId, uint256 maxCost) external nonReentrant returns (uint256 tokenId, uint256 cost) {
        PoolPolicy storage policy = poolPolicies[poolId];

        if (policy.revenueReserve < policy.acquireThreshold || policy.acquireThreshold == 0) {
            revert StrategyVault__BelowAcquireThreshold();
        }

        cost = nftMarket.quoteNextPrice();
        if (cost > maxCost || cost > policy.revenueReserve) {
            revert StrategyVault__InsufficientRevenueReserve();
        }

        policy.revenueReserve -= cost;

        asset.forceApprove(address(nftMarket), cost);
        (tokenId,) = nftMarket.buyNext(address(nftTreasury), cost);

        policy.nftCount += 1;
        nftTreasury.recordAcquisition(poolId, address(nftMarket.nft()), tokenId, cost);

        emit NFTAcquired(poolId, address(nftMarket.nft()), tokenId, cost);
    }

    function totalManagedAssets() public view returns (uint256 assets) {
        assets = asset.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        uint256 supply = shareToken.totalSupply();
        uint256 assetsInVault = totalManagedAssets();

        shares = (assets * (supply + VIRTUAL_SHARES)) / (assetsInVault + VIRTUAL_ASSETS);
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        uint256 supply = shareToken.totalSupply();
        uint256 assetsInVault = totalManagedAssets();

        assets = (shares * (assetsInVault + VIRTUAL_ASSETS)) / (supply + VIRTUAL_SHARES);
    }

    function poolValuation(bytes32 poolId) external view returns (uint256 value) {
        PoolPolicy memory policy = poolPolicies[poolId];
        value = policy.revenueReserve;

        if (policy.valuationMode == VALUATION_MOCK_FLOOR) {
            value += policy.nftCount * nftMarket.quoteNextPrice();
        }
    }
}

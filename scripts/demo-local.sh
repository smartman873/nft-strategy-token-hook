#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[demo-local] running end-to-end strategy lifecycle test"
forge test --match-test test_CanAcquireNftAfterRevenueThreshold -vvv

echo "[demo-local] running revenue capture test"
forge test --match-test test_CapturesRevenueAfterSwap -vvv

echo "[demo-local] summary"
echo "- valuation mode: ZERO_VALUE (0)"
echo "- fee capture: hook afterSwapReturnDelta -> StrategyVault.captureRevenue"
echo "- nft acquisition: permissionless StrategyVault.acquireNFT(poolId, maxCost)"

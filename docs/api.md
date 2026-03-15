# API Surface

## NFTStrategyHook
- `setPoolRevenueConfig(PoolKey, PoolRevenueConfig)`
- `poolRevenueConfig(PoolId)`

## StrategyVault
- `deposit(assets, receiver, minShares)`
- `redeem(shares, receiver, minAssets)`
- `captureRevenue(poolId, token, amount, threshold, mode, nonce)`
- `acquireNFT(poolId, maxCost)`
- `poolPolicies(poolId)`

## FeeRouter
- `setPoolSplit(poolId, strategyBps, treasuryBps, treasuryRecipient)`
- `route(poolId, amount)`

## NFTTreasury
- `recordAcquisition(poolId, nft, tokenId, cost)`
- `inventoryForPool(poolId)`

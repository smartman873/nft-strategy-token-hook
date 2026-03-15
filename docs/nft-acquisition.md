# NFT Acquisition

## Policy
`StrategyVault.acquireNFT(poolId, maxCost)` is permissionless.

## Deterministic Market
`MockNFTMarket` uses linear pricing:

`price = basePrice + priceStep * nextTokenId`

The vault only buys when:
- pool revenue reserve >= threshold
- quoted price <= maxCost
- quoted price <= reserve

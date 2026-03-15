# Specification: NFT Strategy Token Hook

## 1. Objective
Build a deterministic specialized market primitive:

> A strategy share token whose yield path routes a bounded share of swap flow into NFT accumulation, with transparent vault accounting and permissionless NFT acquisition.

## 2. Design Decisions
- Chosen valuation model: `ZERO_VALUE` (primary path).
- NFT acquisition policy: deterministic `MockNFTMarket` linear price curve.
- Redemption model: pure share redemption for fungible token balances.
- Hook model: `afterSwapReturnDelta` fee capture on unspecified token when token matches per-pool config.

## 3. Components
- `NFTStrategyHook`
- `StrategyVault`
- `StrategyShareToken`
- `FeeRouter`
- `NFTTreasury`
- `MockNFTMarket`
- `MockStrategyNFT`

## 4. Revenue Flow
1. Swap executes in v4 pool.
2. Hook computes configured capture share (`revenueShareBps`, max 2000).
3. Hook takes captured amount from `PoolManager` settlement path into vault.
4. Vault routes captured amount via `FeeRouter` to strategy reserve + optional treasury.
5. Any user can trigger `acquireNFT` when threshold is met.

## 5. Determinism Rules
- Configurable per-pool policy with `policyNonce`.
- Bounded fee share (`<= 2000 bps`).
- Deterministic market pricing: `price = basePrice + step * nextTokenId`.
- Permissionless trigger; no keeper required for correctness.

## 6. Pool Config Event Model
- `ConfigSet(poolId, configHash, policyNonce)` in hook.
- `RevenueCaptured(poolId, amount, token)` in hook and vault.
- `NFTAcquired(poolId, nftContract, tokenId, cost)` in vault.
- `SharesMinted(user, shares, deposit)` and `SharesBurned(user, shares, withdraw)` in vault.

## 7. Security Considerations
- Strict role boundaries:
  - hook entrypoints: `onlyPoolManager`
  - config functions: `onlyOwner`
  - vault revenue accounting: `onlyHook`
- Reentrancy protection in vault state-changing functions.
- Share inflation mitigation with virtual assets/shares.
- Stale policy protection using increasing nonce.

## 8. Dependency Policy
- Bootstrap pins `v4-periphery` to `3779387e5d296f39df543d23524b050f89a62917`.
- `v4-core` is aligned to the gitlink expected by the pinned periphery commit.
- Enforced by `scripts/bootstrap.sh` and CI checks.

## 9. Assumptions
- `/context/uniswap` and `/context/atrium` were not present in current workspace.
- A public unchain docs source was cloned into `context/unchain-readthedocs`.
- Conflicting commit-count requirements existed (300 vs 69); validation script defaults to 69 and accepts override argument.

## 10. Tradeoffs
- `ZERO_VALUE` avoids oracle manipulation but excludes NFT value from redemption.
- Mock market enables deterministic demos but is not production marketplace integration.
- Hook capture is bounded and token-selective; pool-level economics must be reviewed before production.

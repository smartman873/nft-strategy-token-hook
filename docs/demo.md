# Demo

## Objective
Prove the complete lifecycle:
fees -> deterministic revenue capture -> vault reserve -> deterministic NFT acquisition -> strategy share accounting.

## Audience Views

### Builder / protocol operator view
1. Deploy strategy stack + demo tokens.
2. Create and configure the hook-backed pool policy.
3. Add liquidity so swaps can execute and generate fee flow.
4. Observe hook revenue capture into `StrategyVault`.
5. Verify deterministic split and threshold gating.
6. Observe deterministic NFT buy and treasury inventory update.

### End user view
1. Deposit `revenueToken` into `StrategyVault` to mint `NSTR` shares.
2. Trade against the configured pool (swap flow).
3. Trigger `acquireNFT(poolId, maxCost)` permissionlessly when threshold is reached.
4. Redeem shares for proportional fungible assets (ZERO_VALUE mode).

## Testnet Command
```bash
make demo-testnet
```

This single command runs:
1. Deployment phase (`script/10_DeployStrategyStack.s.sol`) when required addresses are missing.
2. Lifecycle phase (`script/20_DemoLifecycle.s.sol`) for full end-to-end flow.
3. Final state queries and summary.

## Phase-by-Phase Transaction Flow

### Phase 1: Deploy stack
- Deploy demo ERC20 pair (`DEMO_TOKEN0_ADDRESS`, `DEMO_TOKEN1_ADDRESS`).
- Deploy `FeeRouter`, `NFTTreasury`, `MockNFTMarket`, `StrategyVault`, `NFTStrategyHook`.
- Wire references (`setHook`, `setVault`).
- Persist addresses into `.env` via `ENV:` markers.

### Phase 2: Configure + execute lifecycle
- Configure pool split in `FeeRouter` (`strategyBps=9000`, `treasuryBps=1000`).
- Configure hook `PoolRevenueConfig` (`revenueShareBps=500`, `acquireThreshold=3e16`, `valuationMode=0`).
- Initialize pool + add full-range liquidity.
- User deposits to vault and receives `NSTR` shares.
- User executes swaps through v4 router; hook captures configured revenue into vault reserve.
- User triggers `acquireNFT`; vault buys from deterministic `MockNFTMarket` and records inventory in `NFTTreasury`.
- User redeems part of shares to demonstrate deterministic redemption path.

### Phase 3: Verify and present proof
- Print all transaction hashes.
- Print tx URLs using `BLOCK_EXPLORER_TX_BASE`.
- Query and print:
  - `vault.poolPolicies(poolId)`
  - `treasury.inventoryCount(poolId)`
  - `shareToken.balanceOf(user)`

## What the logs prove
- `RevenueCaptured` path executes only after swaps on the configured hook pool.
- `acquireNFT` is threshold-gated and deterministic.
- NFT custody is auditable in `NFTTreasury`.
- Share mint/redeem behavior is observable from user balances.

## Notes
- Valuation mode is `ZERO_VALUE` in the demo (`valuationMode=0`).
- Reactive network variables are intentionally not used because this project has no reactive integration.

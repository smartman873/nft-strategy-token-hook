# Architecture

## Contracts
- `NFTStrategyHook`: swap hook capture logic.
- `StrategyVault`: revenue accounting, share mint/burn, NFT acquisition.
- `FeeRouter`: per-pool split policy.
- `NFTTreasury`: inventory custody.
- `MockNFTMarket` + `MockStrategyNFT`: deterministic demo market.

## Diagram
```mermaid
flowchart LR
  Swap[Swap] --> Hook[NFTStrategyHook]
  Hook --> Vault[StrategyVault]
  Vault --> Router[FeeRouter]
  Vault --> Market[MockNFTMarket]
  Market --> Treasury[NFTTreasury]
  Vault --> Share[StrategyShareToken]
```

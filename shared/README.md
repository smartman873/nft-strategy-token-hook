# Shared Artifacts

This folder stores ABIs and integration-facing artifacts consumed by the frontend and external tooling.

- `abis/StrategyVault.json`
- `abis/NFTStrategyHook.json`
- `abis/FeeRouter.json`
- `abis/NFTTreasury.json`
- `abis/MockNFTMarket.json`
- `abis/ERC20Minimal.json`

Regenerate contract ABIs with:

```bash
forge inspect StrategyVault abi > shared/abis/StrategyVault.json
forge inspect NFTStrategyHook abi > shared/abis/NFTStrategyHook.json
forge inspect FeeRouter abi > shared/abis/FeeRouter.json
forge inspect NFTTreasury abi > shared/abis/NFTTreasury.json
forge inspect MockNFTMarket abi > shared/abis/MockNFTMarket.json
```

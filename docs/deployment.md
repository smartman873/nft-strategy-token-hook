# Deployment

## Local / Anvil
```bash
./scripts/bootstrap.sh
forge test -vvv
```

## Stack Deploy
```bash
forge script script/10_DeployStrategyStack.s.sol:DeployStrategyStackScript \
  --rpc-url "$RPC_URL" \
  --broadcast
```

## Configure Pool
```bash
forge script script/11_ConfigureStrategyPool.s.sol:ConfigureStrategyPoolScript \
  --rpc-url "$RPC_URL" \
  --broadcast
```

If explorer URL is not known, keep tx hashes from forge output as source of truth.

# Contributing

## Setup
```bash
./scripts/bootstrap.sh
forge test -vvv
```

## Standards
- keep deterministic behavior for policy/accounting paths
- add tests for every state-changing logic change
- avoid introducing unbounded loops in hook/vault hot paths

## Checks
```bash
forge test -vvv
forge fmt --check
./scripts/verify_commits.sh 69
```

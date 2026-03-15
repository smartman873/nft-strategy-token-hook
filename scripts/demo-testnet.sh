#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${RPC_URL:-}" || -z "${OWNER:-}" || -z "${POOL_MANAGER:-}" || -z "${ASSET_TOKEN:-}" ]]; then
  echo "Set RPC_URL OWNER POOL_MANAGER ASSET_TOKEN before running demo-testnet" >&2
  exit 1
fi

forge script script/10_DeployStrategyStack.s.sol:DeployStrategyStackScript \
  --rpc-url "$RPC_URL" \
  --broadcast

echo "[demo-testnet] deploy completed. configure pool policy with script/11_ConfigureStrategyPool.s.sol"

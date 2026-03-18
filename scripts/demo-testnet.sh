#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

upsert_env() {
  local key="$1"
  local value="$2"

  touch "$ENV_FILE"

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    printf "%s=%s\n" "$key" "$value" >> "$ENV_FILE"
  fi
}

apply_env_markers() {
  local logfile="$1"

  while IFS='=' read -r key value; do
    [[ -z "$key" || -z "$value" ]] && continue
    key="${key#ENV:}"
    upsert_env "$key" "$value"
  done < <(grep -oE 'ENV:[A-Z0-9_]+=([0-9a-zA-Zx]+)' "$logfile" || true)
}

latest_run_json() {
  local script_file="$1"
  local chain_id="$2"
  local run_dir="$ROOT_DIR/broadcast/${script_file}/${chain_id}"

  if [[ -f "$run_dir/run-latest.json" ]]; then
    echo "$run_dir/run-latest.json"
    return
  fi

  ls -t "$run_dir"/run-*.json 2>/dev/null | head -n1 || true
}

print_tx_urls() {
  local run_json="$1"
  local label="$2"
  local tx_base="$3"

  if [[ -z "$run_json" || ! -f "$run_json" ]]; then
    echo "[$label] broadcast file not found"
    return
  fi

  echo "[$label] transactions"
  jq -r '.transactions[] | select(.hash != null) | [.transactionType, (.contractName // "call"), (.contractAddress // .to // "-"), .hash] | @tsv' "$run_json" \
    | while IFS=$'\t' read -r tx_type contract_name target hash; do
      if [[ "$tx_base" == "TBD" ]]; then
        echo "- $tx_type | $contract_name | $target | $hash | explorer: TBD"
      else
        echo "- $tx_type | $contract_name | $target | $hash | explorer: ${tx_base}${hash}"
      fi
    done
}

run_script() {
  local script_ref="$1"
  local label="$2"
  local log_file
  local attempt
  local max_attempts=3

  log_file="$(mktemp)"

  echo "[$label] forge script $script_ref"
  for attempt in $(seq 1 "$max_attempts"); do
    if forge script "$script_ref" \
      --rpc-url "$RPC_URL" \
      --private-key "$SEPOLIA_PRIVATE_KEY" \
      --broadcast \
      -vvvv | tee "$log_file"; then
      break
    fi

    if [[ "$attempt" -eq "$max_attempts" ]]; then
      echo "[$label] failed after ${max_attempts} attempts" >&2
      rm -f "$log_file"
      return 1
    fi

    echo "[$label] attempt ${attempt}/${max_attempts} failed, retrying..." >&2
    sleep 5
  done

  apply_env_markers "$log_file"
  local script_file
  script_file="$(basename "${script_ref%%:*}")"
  local run_json
  run_json="$(latest_run_json "$script_file" "$CHAIN_ID")"
  print_tx_urls "$run_json" "$label" "$TX_BASE"

  rm -f "$log_file"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd forge
require_cmd cast
require_cmd jq

load_env

RPC_URL="${SEPOLIA_RPC_URL:-${RPC_URL:-}}"
SEPOLIA_PRIVATE_KEY="${SEPOLIA_PRIVATE_KEY:-${PRIVATE_KEY:-}}"
OWNER_ADDRESS="${OWNER_ADDRESS:-}"

if [[ -z "$RPC_URL" || -z "$SEPOLIA_PRIVATE_KEY" ]]; then
  echo "Set SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY in .env before running demo-testnet" >&2
  exit 1
fi

if [[ -z "$OWNER_ADDRESS" ]]; then
  OWNER_ADDRESS="$(cast wallet address --private-key "$SEPOLIA_PRIVATE_KEY")"
  upsert_env "OWNER_ADDRESS" "$OWNER_ADDRESS"
fi

CHAIN_ID="${SEPOLIA_CHAIN_ID:-1301}"
TX_BASE="${BLOCK_EXPLORER_TX_BASE:-https://sepolia.uniscan.xyz/tx/}"

upsert_env "SEPOLIA_RPC_URL" "$RPC_URL"
upsert_env "SEPOLIA_PRIVATE_KEY" "$SEPOLIA_PRIVATE_KEY"
upsert_env "OWNER_ADDRESS" "$OWNER_ADDRESS"
upsert_env "SEPOLIA_CHAIN_ID" "$CHAIN_ID"
upsert_env "V4_SWAP_ROUTER_ADDRESS" "${V4_SWAP_ROUTER_ADDRESS:-0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba}"
upsert_env "PERMIT2_ADDRESS" "${PERMIT2_ADDRESS:-0x000000000022D473030F116dDEE9F6B43aC78BA3}"

load_env

required_infra=(POOL_MANAGER_ADDRESS POSITION_MANAGER_ADDRESS)
for k in "${required_infra[@]}"; do
  if [[ -z "${!k:-}" ]]; then
    echo "Missing $k in .env" >&2
    exit 1
  fi
done

echo "[demo-testnet] chain_id=$CHAIN_ID owner=$OWNER_ADDRESS"
echo "[demo-testnet] owner_native_balance=$(cast balance --rpc-url "$RPC_URL" "$OWNER_ADDRESS")"

required_stack=(
  DEMO_TOKEN0_ADDRESS
  DEMO_TOKEN1_ADDRESS
  REVENUE_TOKEN_ADDRESS
  FEE_ROUTER_ADDRESS
  NFT_TREASURY_ADDRESS
  MOCK_NFT_MARKET_ADDRESS
  STRATEGY_VAULT_ADDRESS
  NFT_STRATEGY_HOOK_ADDRESS
  STRATEGY_SHARE_TOKEN_ADDRESS
)

needs_deploy=0
for k in "${required_stack[@]}"; do
  if [[ -z "${!k:-}" ]]; then
    needs_deploy=1
    break
  fi
done

if [[ "${FORCE_DEPLOY:-0}" == "1" ]]; then
  needs_deploy=1
fi

if [[ "$needs_deploy" == "1" ]]; then
  echo "[demo-testnet] phase 1/3 deploy stack"
  run_script "script/10_DeployStrategyStack.s.sol:DeployStrategyStackScript" "deploy"
  load_env
else
  echo "[demo-testnet] phase 1/3 deploy stack skipped (addresses already in .env)"
fi

echo "[demo-testnet] phase 2/3 run lifecycle demo"
run_script "script/20_DemoLifecycle.s.sol:DemoLifecycleScript" "lifecycle"
load_env

echo "[demo-testnet] phase 3/3 final state summary"
echo "- DEMO_POOL_ID=${DEMO_POOL_ID:-unset}"
echo "- STRATEGY_VAULT_ADDRESS=${STRATEGY_VAULT_ADDRESS:-unset}"
echo "- NFT_TREASURY_ADDRESS=${NFT_TREASURY_ADDRESS:-unset}"
echo "- STRATEGY_SHARE_TOKEN_ADDRESS=${STRATEGY_SHARE_TOKEN_ADDRESS:-unset}"
echo "- DEMO_USER_ADDRESS=${DEMO_USER_ADDRESS:-unset}"

if [[ -n "${DEMO_POOL_ID:-}" && -n "${STRATEGY_VAULT_ADDRESS:-}" ]]; then
  echo "- vault.poolPolicies = $(cast call --rpc-url "$RPC_URL" "$STRATEGY_VAULT_ADDRESS" 'poolPolicies(bytes32)((uint128,uint8,uint64,uint256,uint256))' "$DEMO_POOL_ID")"
fi

if [[ -n "${DEMO_POOL_ID:-}" && -n "${NFT_TREASURY_ADDRESS:-}" ]]; then
  echo "- treasury.inventoryCount = $(cast call --rpc-url "$RPC_URL" "$NFT_TREASURY_ADDRESS" 'inventoryCount(bytes32)(uint256)' "$DEMO_POOL_ID")"
fi

if [[ -n "${DEMO_USER_ADDRESS:-}" && -n "${STRATEGY_SHARE_TOKEN_ADDRESS:-}" ]]; then
  echo "- user.shareBalance = $(cast call --rpc-url "$RPC_URL" "$STRATEGY_SHARE_TOKEN_ADDRESS" 'balanceOf(address)(uint256)' "$DEMO_USER_ADDRESS")"
fi

echo "[demo-testnet] .env updated with deployment + demo addresses"

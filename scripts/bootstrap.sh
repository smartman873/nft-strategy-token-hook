#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PINNED_PERIPHERY_COMMIT="3779387e5d296f39df543d23524b050f89a62917"

printf "[bootstrap] syncing submodules...\n"
git submodule update --init --recursive

printf "[bootstrap] pinning v4-periphery to %s\n" "$PINNED_PERIPHERY_COMMIT"
git -C lib/uniswap-hooks/lib/v4-periphery fetch --all --tags
git -C lib/uniswap-hooks/lib/v4-periphery checkout "$PINNED_PERIPHERY_COMMIT"

EXPECTED_CORE_COMMIT="$(git -C lib/uniswap-hooks/lib/v4-periphery ls-tree HEAD lib/v4-core | awk '{print $3}')"
if [[ -z "$EXPECTED_CORE_COMMIT" ]]; then
  echo "[bootstrap] unable to determine v4-core commit from pinned v4-periphery" >&2
  exit 1
fi

printf "[bootstrap] aligning v4-core to %s\n" "$EXPECTED_CORE_COMMIT"
git -C lib/uniswap-hooks/lib/v4-core fetch --all --tags
git -C lib/uniswap-hooks/lib/v4-core checkout "$EXPECTED_CORE_COMMIT"

CURRENT_PERIPHERY="$(git -C lib/uniswap-hooks/lib/v4-periphery rev-parse HEAD)"
CURRENT_CORE="$(git -C lib/uniswap-hooks/lib/v4-core rev-parse HEAD)"

if [[ "$CURRENT_PERIPHERY" != "$PINNED_PERIPHERY_COMMIT" ]]; then
  echo "[bootstrap] mismatch: v4-periphery expected $PINNED_PERIPHERY_COMMIT got $CURRENT_PERIPHERY" >&2
  exit 1
fi
if [[ "$CURRENT_CORE" != "$EXPECTED_CORE_COMMIT" ]]; then
  echo "[bootstrap] mismatch: v4-core expected $EXPECTED_CORE_COMMIT got $CURRENT_CORE" >&2
  exit 1
fi

printf "[bootstrap] done\n"

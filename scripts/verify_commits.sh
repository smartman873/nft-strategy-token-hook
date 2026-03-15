#!/usr/bin/env bash
set -euo pipefail

EXPECTED="${1:-69}"
CURRENT="$(git rev-list --count HEAD)"

if [[ "$CURRENT" != "$EXPECTED" ]]; then
  echo "commit-count-check: expected=$EXPECTED actual=$CURRENT"
  exit 1
fi

echo "commit-count-check: ok ($CURRENT commits)"

#!/usr/bin/env bash
# pnpm test — runs every tests/kit/*.test.sh and fails if any of them fails.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

failed=()
for t in tests/kit/*.test.sh; do
  echo "==> $t"
  bash "$t" || failed+=("$t")
done
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}" >&2; exit 1
fi
echo "All kit tests passed."

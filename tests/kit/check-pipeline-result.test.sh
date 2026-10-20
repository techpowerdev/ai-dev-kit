#!/usr/bin/env bash
# Tests scripts/check-pipeline-result.sh against a fake gh with canned API responses.
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
SINCE=2026-10-20T18:00:00Z
bot='"user":{"login":"claude[bot]","type":"Bot"}'
human='"user":{"login":"someone","type":"User"}'

# check <description> <expect pass|fail> <comments-json> <pulls-json> [expect-comment-posted yes|no]
check() {
  local d="$tmp/$RANDOM"; mkdir -p "$d"
  printf '%s' "$3" >"$d/comments.json"; printf '%s' "$4" >"$d/pulls.json"; : >"$d/log"
  if FAKE_GH_RESPONSES="$d" FAKE_GH_LOG="$d/log" GITHUB_REPOSITORY=o/r RUN_URL=https://run/1 PATH="$PWD/tests/kit/fake-gh:$PATH" \
       bash scripts/check-pipeline-result.sh 12 "$SINCE" >"$d/out" 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$2" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ $1: expected $2, got $got"; sed 's/^/       /' "$d/out"; fi
  if [[ "${5:-}" == yes ]]; then
    if grep -q '^issue comment 12 ' "$d/log" && grep -q 'https://run/1' "$d/log"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ $1: expected a failure comment on the issue"; fi
  elif [[ "${5:-}" == no ]]; then
    if grep -q '^issue comment' "$d/log"; then fail=$((fail+1)); echo "   ✗ $1: did not expect a comment"; else pass=$((pass+1)); fi
  fi
}

check "bot spec/plan/progress comment"    pass "[{$bot,\"created_at\":\"2026-10-20T18:10:00Z\"}]" '[]' no
check "PR from ai/12-* updated"           pass '[]' '[{"head":{"ref":"ai/12-push-step"},"updated_at":"2026-10-20T18:20:00Z"}]' no
check "nothing at all"                    fail '[]' '[]' yes
check "only a human comment"              fail "[{$human,\"created_at\":\"2026-10-20T18:10:00Z\"}]" '[]' yes
check "only an old bot comment"           fail "[{$bot,\"created_at\":\"2026-10-20T17:00:00Z\"}]" '[]' yes
check "PR for another issue"              fail '[]' '[{"head":{"ref":"ai/123-other"},"updated_at":"2026-10-20T18:20:00Z"}]' yes
check "PR not touched since start"        fail '[]' '[{"head":{"ref":"ai/12-old"},"updated_at":"2026-10-20T10:00:00Z"}]' yes

echo "   check-pipeline-result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

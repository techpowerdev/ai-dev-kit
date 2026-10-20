#!/usr/bin/env bash
# Tests scripts/check-review-posted.sh against a fake gh with canned API responses.
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
SINCE=2026-10-20T08:00:00Z
# check <description> <expect pass|fail> <comments-json> <reviews-json>
check() {
  local d="$tmp/$RANDOM"; mkdir -p "$d"
  printf '%s' "$3" >"$d/comments.json"; printf '%s' "$4" >"$d/reviews.json"
  if FAKE_GH_RESPONSES="$d" FAKE_GH_LOG=/dev/null GITHUB_REPOSITORY=o/r PATH="$PWD/tests/kit/fake-gh:$PATH" \
       bash scripts/check-review-posted.sh 8 "$SINCE" >"$d/out" 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$2" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ $1: expected $2, got $got"; sed 's/^/       /' "$d/out"; fi
}
bot='"user":{"login":"claude[bot]","type":"Bot"}'
otherbot='"user":{"login":"github-actions[bot]","type":"Bot"}'
human='"user":{"login":"someone","type":"User"}'

check "bot review comment after start"    pass "[{$bot,\"created_at\":\"2026-10-20T08:50:04Z\",\"body\":\"## AI Review: PR #8\"}]" '[]'
check "bot PR review after start"         pass '[]' "[{$bot,\"submitted_at\":\"2026-10-20T08:50:04Z\",\"body\":\"## AI Review\"}]"
check "no comments at all"                fail '[]' '[]'
check "human comment does not count"      fail "[{$human,\"created_at\":\"2026-10-20T08:50:04Z\",\"body\":\"## AI Review looks fine\"}]" '[]'
check "bot comment without the marker"    fail "[{$bot,\"created_at\":\"2026-10-20T08:50:04Z\",\"body\":\"Claude is working…\"}]" '[]'
check "old review from an earlier run"    fail "[{$bot,\"created_at\":\"2026-10-20T07:00:00Z\",\"body\":\"## AI Review\"}]" '[]'
check "another bot does not count"      fail "[{$otherbot,\"created_at\":\"2026-10-20T08:50:04Z\",\"body\":\"## AI Review\"}]" '[]'
check "leading whitespace and CRLF ok"    pass "[{$bot,\"created_at\":\"2026-10-20T08:50:04Z\",\"body\":\" \\r\\n## AI Review\"}]" '[]'
check "paginated: match on page 2"        pass "[{$human,\"created_at\":\"2026-10-20T08:10:00Z\",\"body\":\"hi\"}][{$bot,\"created_at\":\"2026-10-20T08:20:00Z\",\"body\":\"## AI Review\"}]" '[]'

echo "   check-review-posted: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

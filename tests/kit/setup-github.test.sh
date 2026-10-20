#!/usr/bin/env bash
# Tests scripts/setup-github.sh against a fake gh, checking the JSON it would send.
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

# run <name> <has-package.json 0|1> [script args...]
run() {
  local name="$1" pkg="$2"; shift 2
  export FAKE_GH_LOG="$tmp/$name.log" FAKE_HAS_PKG="$pkg"
  : >"$FAKE_GH_LOG"
  PATH="$PWD/tests/kit/fake-gh:$PATH" bash scripts/setup-github.sh owner/repo me "$@" >"$tmp/$name.out" 2>&1
}
# body <name> <api-path> → the JSON sent to that path
body() { grep -A1 -F "$2" "$tmp/$1.log" | tail -1; }
# check <description> <name> <api-path> <jq expression that must be true>
check() {
  if body "$2" "$3" | jq -e "$4" >/dev/null 2>&1; then pass=$((pass+1))
  else fail=$((fail+1)); echo "   ✗ $1"; echo "     sent: $(body "$2" "$3")"; fi
}
P=branches/main/protection
CHECKS='["lint · typecheck · test · build","e2e (Playwright)"]'

run team 1
check "team: 1 approval + CODEOWNERS"      team $P '.required_pull_request_reviews.required_approving_review_count == 1 and .required_pull_request_reviews.require_code_owner_reviews'
check "team: admins may bypass"            team $P '.enforce_admins == false'
check "team: CI required"                  team $P ".required_status_checks.contexts == $CHECKS and .required_status_checks.strict"
check "team: no force push, linear"        team $P '.allow_force_pushes == false and .required_linear_history'

run solo 1 --solo
check "solo: no approval, no CODEOWNERS"   solo $P '.required_pull_request_reviews.required_approving_review_count == 0 and (.required_pull_request_reviews.require_code_owner_reviews | not)'
check "solo: rules apply to admins"        solo $P '.enforce_admins == true'
check "solo: CI still required"            solo $P ".required_status_checks.contexts == $CHECKS"

run nopkg 0 --solo
check "no package.json: CI not required"   nopkg $P '.required_status_checks == null'

check "production needs a reviewer"        team environments/production '.reviewers | length == 1'
check "production: protected branches only" team environments/production '.deployment_branch_policy.protected_branches'
check "post-deploy-report waits 30 min"    team environments/post-deploy-report '.wait_timer == 30'

# Plan limits: a private repo gets a warning; rejected rules still create the environment.
FAKE_VISIBILITY=private run private 1 --solo
if grep -q "is private. Required reviewers" "$tmp/private.out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ private repo should warn about Gate 4"; fi
check "private repo that accepts the rules keeps the reviewer" private environments/production '.reviewers | length == 1'
if grep -q "Gate 4 (approval before production) is NOT enforced" "$tmp/private.out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ private repo should repeat the Gate 4 warning at the end"; fi
if grep -q "Required reviewers (Gate 4) and wait timers only" "$tmp/solo.out" || grep -q "NOT enforced" "$tmp/solo.out"; then fail=$((fail+1)); echo "   ✗ public repo should not warn"; else pass=$((pass+1)); fi
FAKE_VISIBILITY=internal run internal 1 --solo
if grep -q "NOT enforced" "$tmp/internal.out"; then fail=$((fail+1)); echo "   ✗ internal (Enterprise) repo should not warn"; else pass=$((pass+1)); fi
FAKE_VISIBILITY=private FAKE_REJECT_RULES=1 run rejected 1 --solo
check "rejected rules: production still created" rejected environments/production '.deployment_branch_policy.protected_branches and (.reviewers == null)'
check "rejected rules: report env still created" rejected environments/post-deploy-report '.wait_timer == null'
if grep -q "rejected the protection rules for 'production'" "$tmp/rejected.out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ rejected rules should be reported"; fi
if grep -q "requires approval from" "$tmp/rejected.out"; then fail=$((fail+1)); echo "   ✗ must not claim Gate 4 when rules were rejected"; else pass=$((pass+1)); fi
# expect_stop <name> <description> [env...]: the script must exit non-zero
expect_stop() {
  local name="$1" desc="$2"; shift 2
  if env "$@" FAKE_GH_LOG="$tmp/$name.log" FAKE_HAS_PKG=1 PATH="$PWD/tests/kit/fake-gh:$PATH" \
       bash scripts/setup-github.sh owner/repo me --solo >"$tmp/$name.out" 2>&1; then
    fail=$((fail+1)); echo "   ✗ $desc"
  else pass=$((pass+1)); fi
}
# expect_ok <name> <description> [env...]: the script must exit 0
expect_ok() {
  local name="$1" desc="$2"; shift 2
  if env "$@" FAKE_GH_LOG="$tmp/$name.log" FAKE_HAS_PKG=1 PATH="$PWD/tests/kit/fake-gh:$PATH" \
       bash scripts/setup-github.sh owner/repo me --solo >"$tmp/$name.out" 2>&1; then
    pass=$((pass+1))
  else fail=$((fail+1)); echo "   ✗ $desc"; fi
}
expect_ok rejected_ok "a private plan-limit rejection should still finish (exit 0)" FAKE_VISIBILITY=private FAKE_REJECT_RULES=1
expect_stop fallbackfail "private: if the fallback PUT also fails, stop" FAKE_VISIBILITY=private FAKE_REJECT_ALL_ENV=1
expect_stop private403 "private: a non-422 error (403) must stop, not drop Gate 4" FAKE_VISIBILITY=private FAKE_REJECT_RULES=1 FAKE_REJECT_STATUS=403
if grep -q 'environments/production' "$tmp/private403.log" 2>/dev/null; then fail=$((fail+1)); echo "   ✗ 403: production must not be created without rules"; else pass=$((pass+1)); fi

# On a public repo a rejection is never a plan limit: stop, and never create production without rules.
if FAKE_VISIBILITY=public FAKE_REJECT_RULES=1 FAKE_GH_LOG="$tmp/pubreject.log" FAKE_HAS_PKG=1 \
     PATH="$PWD/tests/kit/fake-gh:$PATH" bash scripts/setup-github.sh owner/repo me --solo >"$tmp/pubreject.out" 2>&1; then
  fail=$((fail+1)); echo "   ✗ public repo: a rejected Gate 4 must stop the script"
else pass=$((pass+1)); fi
if grep -q 'environments/production' "$tmp/pubreject.log" 2>/dev/null; then
  fail=$((fail+1)); echo "   ✗ public repo: production must not be created without its rules"
else pass=$((pass+1)); fi
if grep -q "HTTP 422" "$tmp/pubreject.out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ the real GitHub error should be shown"; fi

if ! grep -q "Mode: solo" "$tmp/solo.out"; then fail=$((fail+1)); echo "   ✗ solo mode not reported"; else pass=$((pass+1)); fi
if PATH="$PWD/tests/kit/fake-gh:$PATH" FAKE_GH_LOG=/dev/null bash scripts/setup-github.sh o/r me --bogus >/dev/null 2>&1; then
  fail=$((fail+1)); echo "   ✗ unknown flag should exit non-zero"
else pass=$((pass+1)); fi

echo "   setup-github: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

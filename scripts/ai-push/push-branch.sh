#!/usr/bin/env bash
# Usage: push-branch.sh --branch B --tip SHA --mode pipeline|pr [--expected-old SHA] [--repo DIR] [--remote NAME]
# Env: PUSH_TOKEN (optional: without it, git uses whatever access the remote allows,
#      which is how the tests push to a local bare repo)
#
# Trusted. Pushes TIP to refs/heads/B, fast-forward only, nothing else:
#   - the token goes in through GIT_CONFIG_* environment variables as an http
#     extraheader, so it is never written to .git/config and never in argv
#   - the remote branch must not have moved during the run (decision 5):
#       pr:       remote tip == --expected-old (the PR head when the job started)
#       pipeline: remote branch absent, or == --expected-old (resuming from it, A3)
#     If the remote already equals TIP (a re-run), nothing is pushed.
#   - no force, no "+" refspec, no --all/--mirror/--tags, hooks off
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

branch=""; tip=""; mode=""; expected_old=""; repo=.; remote=origin
while (( $# )); do
  case "$1" in
    --branch) branch="$2"; shift 2 ;;
    --tip) tip="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --expected-old) expected_old="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --remote) remote="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$mode" =~ ^(pipeline|pr)$ ]] || { echo "--mode must be pipeline or pr" >&2; exit 2; }
ai_validate_branch "$branch" || ai_fail "Refusing to push to '$branch'."
[[ "$tip" =~ ^[0-9a-f]{40}$ ]] || ai_fail "--tip must be a full commit SHA."
[[ -z "$expected_old" || "$expected_old" =~ ^[0-9a-f]{40}$ ]] || ai_fail "--expected-old must be a full commit SHA."
cd "$repo"
ai_git rev-parse --verify --quiet "$tip^{commit}" >/dev/null || ai_fail "The tip commit is not in this repo."

if [[ -n "${PUSH_TOKEN:-}" ]]; then
  auth="$(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 | tr -d '\n')"
  echo "::add-mask::$auth"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth"
fi

remote_old="$(ai_git ls-remote "$remote" "refs/heads/$branch" | awk '{print $1}')"
if [[ "$remote_old" == "$tip" ]]; then
  echo "origin/$branch is already at $tip: nothing to push."
  ai_output pushed false
  exit 0
fi
case "$mode" in
  pr)
    [[ -n "$expected_old" && "$remote_old" == "$expected_old" ]] \
      || ai_fail "The PR branch $branch moved during this run (expected ${expected_old:-?}, found ${remote_old:-none}). Not pushing; re-run on the new head." ;;
  pipeline)
    if [[ -n "$remote_old" && "$remote_old" != "$expected_old" ]]; then
      ai_fail "origin/$branch exists or moved during this run (found $remote_old, expected ${expected_old:-no branch}). Not pushing."
    fi ;;
esac

ai_git push --no-verify --porcelain "$remote" "$tip:refs/heads/$branch"
ai_output pushed true
echo "Pushed $tip to $branch."

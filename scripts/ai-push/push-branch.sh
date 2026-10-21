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
#   - fast-forward only: the old remote tip must be in this repo and an ancestor of
#     TIP, checked here right before the push (not only by inspect-bundle.sh)
#   - the only force-like flag is a lease pinned to the value just checked, which makes
#     the push fail if the remote moved; it never rewrites history because of the
#     ancestry check above. No bare --force, no "+" refspec, no --all/--mirror/--tags,
#     hooks off
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
  echo "::add-mask::$PUSH_TOKEN"
  auth="$(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 | tr -d '\n')"
  echo "::add-mask::$auth"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth"
fi

ls_out="$(ai_git ls-remote "$remote" "refs/heads/$branch")" || ai_fail "Could not read refs/heads/$branch from $remote."
remote_old="$(printf '%s' "$ls_out" | awk '{print $1}')"
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
    # Starting fresh: the branch must not exist. Resuming: it must still be exactly
    # where we started (not moved, not deleted).
    if [[ "$remote_old" != "$expected_old" ]]; then
      ai_fail "origin/$branch changed during this run (found ${remote_old:-no branch}, expected ${expected_old:-no branch}). Not pushing."
    fi ;;
esac

# Fast-forward only, checked here and not just trusted from inspect-bundle.sh: with a
# lease git would otherwise accept a history rewrite.
if [[ -n "$remote_old" ]]; then
  ai_git cat-file -e "$remote_old^{commit}" 2>/dev/null \
    || ai_fail "origin/$branch is at $remote_old, which is not in this repo. Not pushing."
  ai_git merge-base --is-ancestor "$remote_old" "$tip" \
    || ai_fail "$tip does not build on origin/$branch ($remote_old): not a fast-forward. Not pushing."
fi
# The lease closes the gap between ls-remote and push: the push only happens if the
# remote branch is still exactly what was checked above (absent, or expected_old).
ai_git push --no-verify --porcelain "--force-with-lease=refs/heads/$branch:$remote_old" "$remote" "$tip:refs/heads/$branch"
ai_output pushed true
echo "Pushed $tip to $branch."

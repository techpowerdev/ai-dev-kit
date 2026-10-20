#!/usr/bin/env bash
# Usage: inspect-bundle.sh --mode pipeline|pr|none --number N --base SHA --in DIR
#          [--expected-branch B] [--repo DIR] [--default-branch NAME] [--labeler FILE]
#
# Trusted, no token. Checks the untrusted artifact from make-bundle.sh and, if it is
# acceptable, fetches the commits into refs/ai-incoming/head of the trusted checkout.
# Never checks out Claude's tree and never runs repo hooks (see ai_git).
#
# Outputs (GITHUB_OUTPUT): commits, branch, tip, workflows (count of changed
# .github/workflows files), high_risk (true if a changed path matches a risk:high glob
# in the labeler file).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

mode=""; number=""; base=""; in=""; expected=""; repo=.; default_branch=main; labeler=""
while (( $# )); do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --number) number="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --in) in="$2"; shift 2 ;;
    --expected-branch) expected="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --default-branch) default_branch="$2"; shift 2 ;;
    --labeler) labeler="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$mode" =~ ^(pipeline|pr|none)$ && "$number" =~ ^[0-9]+$ && -n "$base" && -n "$in" ]] || { echo "usage: see header" >&2; exit 2; }
[[ "$base" =~ ^[0-9a-f]{40}$ ]] || ai_fail "base must be a full commit SHA"
[[ "$mode" != pr || -n "$expected" ]] || ai_fail "--expected-branch is required in pr mode"
if [[ -n "$labeler" ]]; then
  [[ -f "$labeler" ]] || ai_fail "Labeler file $labeler not found: cannot decide whether the change is high risk."
  [[ -n "$(ai_high_risk_globs "$labeler")" ]] || ai_fail "No risk:high globs in $labeler: cannot decide whether the change is high risk."
fi
cd "$repo"

nothing() { echo "nothing to push"; ai_output commits 0; exit 0; }
first_line() { head -n 1 "$1" 2>/dev/null | tr -d '\r' || true; }

# 1. status
status="$(first_line "$in/status" | LC_ALL=C tr -cd '[:lower:]')"
claimed="$(first_line "$in/commits" | LC_ALL=C tr -cd '0-9' | cut -c1-6)"
if [[ "$mode" == none && "$status" != none && "$status" != empty && -n "$status" ]]; then
  ai_fail "This run may not push, but the artifact says '$status'."
fi
case "$status" in
  ""|empty)
    (( ${claimed:-0} == 0 )) || ai_fail "The artifact says 'empty' but counts ${claimed} commit(s): make-bundle.sh did not finish."
    nothing ;;
  failed) ai_fail "make-bundle.sh failed in the Claude job; see that job's log." ;;
  refused) ai_fail "The Claude job refused to bundle (for example more than one ai/$number-* branch)." ;;
  none)
    [[ "$mode" == none ]] || ai_fail "The artifact says 'none' but this run may push."
    ai_output commits "${claimed:-0}"; echo "${claimed:-0} commit(s) that this run may not push."; exit 0 ;;
  bundle) [[ "$mode" != none ]] || ai_fail "Unexpected bundle in mode none." ;;
  *) ai_fail "Unknown bundle status." ;;
esac

# 2. branch name
branch="$(first_line "$in/branch")"
if [[ "$mode" == pipeline ]]; then
  ai_validate_branch "$branch" "$number" || ai_fail "Refusing branch name '$branch': must be ai/$number-<slug>."
else
  ai_validate_branch "$branch" || ai_fail "Refusing branch name '$branch': must match ai/<n>-<slug>."
  [[ -z "$expected" || "$branch" == "$expected" ]] || ai_fail "Bundle branch '$branch' is not the PR head '$expected'."
fi

# 3. exactly one head, and it is that branch
bundle="$in/ai.bundle"
[[ -f "$bundle" && ! -L "$bundle" ]] || ai_fail "No bundle file."
heads="$(ai_git bundle list-heads "$bundle" 2>/dev/null || true)"
[[ "$(printf '%s\n' "$heads" | grep -c .)" -eq 1 ]] || ai_fail "The bundle must contain exactly one head."
[[ "$(printf '%s' "$heads" | awk '{print $2}')" == "refs/heads/$branch" ]] || ai_fail "The bundle head is not refs/heads/$branch."

# 4. verify and fetch with an explicit refspec
ai_git bundle verify "$bundle" >/dev/null 2>&1 || ai_fail "The bundle does not verify against this repo (missing base or corrupt)."
ai_git update-ref -d refs/ai-incoming/head 2>/dev/null || true
ai_git fetch --quiet --no-tags --no-write-fetch-head "$bundle" "refs/heads/$branch:refs/ai-incoming/head" \
  || ai_fail "Could not fetch the bundle."
tip="$(ai_git rev-parse --verify 'refs/ai-incoming/head^{commit}')"

# 5. history: the base is in the new history, and the base is something we trust
ai_git merge-base --is-ancestor "$base" "$tip" || ai_fail "The commits do not build on the base commit."
if [[ "$mode" == pipeline ]]; then
  resume_tip="$(ai_git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" || true)"
  if ! ai_git merge-base --is-ancestor "$base" "refs/remotes/origin/$default_branch" 2>/dev/null \
     && [[ "$base" != "$resume_tip" ]]; then
    ai_fail "The base is neither on $default_branch nor the current tip of origin/$branch."
  fi
fi

# 6. commit count
commits="$(ai_git rev-list --count "$base..$tip")"
(( commits > 0 )) || nothing
(( commits <= 200 )) || ai_fail "$commits commits is more than the 200 allowed in one push."

# 7. files: no AI scratch files committed; report workflow and high-risk paths
# --no-renames: a rename shows as delete + add, so moving a file out of a guarded
# directory still counts. quotePath=false and -z: non-ASCII names stay as they are
# instead of being C-quoted (which would dodge the anchored checks).
changed="$(ai_git -c core.quotePath=false diff --no-renames --name-only -z "$base" "$tip" | tr '\0' '\n')"
scratch="$(printf '%s\n' "$changed" | grep -E '(^|/)\.ai-(pr-body|comment|review)\.md$' || true)"
[[ -z "$scratch" ]] || ai_fail "AI scratch files were committed: $(printf '%s' "$scratch" | tr '\n' ' ')"
workflows="$(printf '%s\n' "$changed" | grep -c '^\.github/workflows/' || true)"
if (( workflows > 0 )); then
  ai_warn "This push changes $workflows file(s) under .github/workflows/: $(printf '%s\n' "$changed" | grep '^\.github/workflows/' | head -20 | tr '\n' ' ')"
fi
high_risk=false; risky=""
if [[ -n "$labeler" && -f "$labeler" ]]; then
  globs="$(ai_high_risk_globs "$labeler")"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    while IFS= read -r g; do
      [[ -z "$g" ]] && continue
      if ai_path_matches "$p" "$g"; then risky="$risky $p"; break; fi
    done <<<"$globs"
  done <<<"$changed"
  if [[ -n "$risky" ]]; then high_risk=true; ai_warn "High-risk paths changed:$(printf '%s' "$risky" | cut -c1-500)"; fi
fi

# 8. uncommitted work is reported, never pushed (decision 6)
if [[ -s "$in/uncommitted.txt" ]]; then
  ai_warn "Claude left uncommitted changes (not pushed): $(head -n 50 "$in/uncommitted.txt" | head -c 2000 | tr '\n' ' ')"
fi

# 9. outputs
ai_output commits "$commits"
ai_output branch "$branch"
ai_output tip "$tip"
ai_output workflows "$workflows"
ai_output high_risk "$high_risk"
echo "OK: $commits commit(s) on $branch, tip $tip, high_risk=$high_risk."

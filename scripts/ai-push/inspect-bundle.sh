#!/usr/bin/env bash
# Usage: inspect-bundle.sh --mode pipeline|pr|none --number N --base SHA --in DIR
#          [--expected-branch B] [--repo DIR] [--default-branch NAME] [--labeler FILE]
#
# Trusted, no token. Checks the untrusted artifact from make-bundle.sh and, if it is
# acceptable, fetches the commits into refs/ai-incoming/head of the trusted checkout.
# Never checks out Claude's tree and never runs repo hooks (see ai_git).
#
# Outputs (GITHUB_OUTPUT): commits, branch, tip, workflows (count of changed
# .github/workflows files), agent_config (count of changed paths that configure the AI
# or this push path: .claude/**, CLAUDE.md, scripts/ai-push/**), high_risk (true if a
# changed path matches a risk:high glob in the labeler file).
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
# Absolute paths: the script changes directory to the repo below.
abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
in="$(abs "$in")"
[[ -n "$labeler" ]] && labeler="$(abs "$labeler")"
# Before git 2.46, fetch.fsckObjects does not check objects that come from a bundle.
git_version="$(git version | awk '{print $3}')"
if [[ "$(printf '%s\n2.46.0\n' "$git_version" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" != "2.46.0" ]]; then
  ai_fail "git $git_version is too old: 2.46 or newer is needed to fsck objects from a bundle."
fi
globs=""
if [[ -n "$labeler" ]]; then
  [[ -f "$labeler" ]] || ai_fail "Labeler file $labeler not found: cannot decide whether the change is high risk."
  globs="$(ai_high_risk_globs "$labeler" 2>"${TMPDIR:-/tmp}/ai-globs.err.$$")" \
    || ai_fail "$(cat "${TMPDIR:-/tmp}/ai-globs.err.$$")"
  rm -f "${TMPDIR:-/tmp}/ai-globs.err.$$"
  [[ -n "$globs" ]] || ai_fail "No risk:high globs in $labeler: cannot decide whether the change is high risk."
fi
cd "$repo"
[[ -f "$in/status" && ! -L "$in/status" ]] || ai_fail "No status file in the artifact ($in): it may not have been downloaded. Not treating that as 'nothing to push'."

nothing() { echo "nothing to push"; ai_output commits 0; exit 0; }
first_line() { head -n 1 "$1" 2>/dev/null | tr -d '\r' || true; }

# 1. status
status="$(first_line "$in/status" | LC_ALL=C tr -cd '[:lower:]')"
claimed="$(first_line "$in/commits" | LC_ALL=C tr -cd '0-9' | cut -c1-6)"
if [[ "$mode" == none && "$status" != none && "$status" != empty && -n "$status" ]]; then
  ai_fail "This run may not push, but the artifact says '$status'."
fi
case "$status" in
  empty)
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
if [[ "$mode" == pr ]]; then
  pr_head="$(ai_git rev-parse --verify --quiet "refs/remotes/origin/$expected^{commit}" || true)"
  [[ -n "$pr_head" && "$base" == "$pr_head" ]] || ai_fail "In pr mode the base must be the current head of origin/$expected (${pr_head:-not found})."
fi
if [[ "$mode" == pipeline ]]; then
  resume_tip="$(ai_git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" || true)"
  if [[ -n "$resume_tip" ]]; then
    # The branch exists: only a resume from its exact tip may push to it (A3).
    [[ "$base" == "$resume_tip" ]] \
      || ai_fail "origin/$branch exists, so the base must be its tip ($resume_tip) to resume it; got $base."
  elif ! ai_git merge-base --is-ancestor "$base" "refs/remotes/origin/$default_branch" 2>/dev/null; then
    ai_fail "The base is not on $default_branch."
  fi
fi

# 6. commit count: only the AI's commits. Commits already on the default branch (the AI
# merged it in) are not the AI's work and do not count.
main_ref="refs/remotes/origin/$default_branch"
ai_git rev-parse --verify --quiet "$main_ref^{commit}" >/dev/null || ai_fail "origin/$default_branch is not in the trusted checkout."
commits="$(ai_git rev-list --count "$base..$tip" "^$main_ref")"
(( commits > 0 )) || nothing
(( commits <= 200 )) || ai_fail "$commits commits is more than the 200 allowed in one push."

# 7. files: no AI scratch files committed; report workflow and high-risk paths
# --no-renames: a rename shows as delete + add, so moving a file out of a guarded
# directory still counts. quotePath=false and -z: non-ASCII names stay as they are
# instead of being C-quoted (which would dodge the anchored checks).
# The paths are the union of:
#   1. the PR's effect: the diff from the merge base with the default branch to the tip.
#      This is what merging the PR would change on main. It catches a merge that keeps
#      the AI's side ("merge -s ours", or "ours" in a conflict) and so silently undoes a
#      fix main made in a guarded file: no AI commit wrote that, but merging it would.
#      After a clean merge of main the merge base is main's tip, so main's own changes
#      are not blamed on the AI. More than one merge base (a criss-cross merge) is
#      ambiguous: fail.
#   2. the AI's commits: base..tip minus everything on the default branch.
#      - every non-merge commit: all paths it changed, so a change that a later commit
#        reverts still counts (the diff in 1 would hide it)
#      - every merge: dense-combined (git 2.31+, checked above) lists the paths whose
#        result differs from all parents, i.e. what the merge itself wrote. 1 and the
#        non-merge commits already cover this (the tests pass without it); it stays as
#        a second layer that does not depend on how git log treats merges by default.
# On a resumed branch, 1 also lists paths from earlier runs on the branch. That
# over-reports, which is the safe direction.
# A git error fails the script (pipefail), so it can never read as "no paths changed"
# and turn the high-risk gate open.
merge_bases="$(ai_git merge-base --all "$main_ref" "$tip")" \
  || ai_fail "The commits share no history with origin/$default_branch."
[[ "$(printf '%s\n' "$merge_bases" | grep -c .)" == 1 ]] \
  || ai_fail "The commits have more than one merge base with origin/$default_branch (criss-cross merge): cannot tell what the PR changes."
effect_paths="$(ai_git -c core.quotePath=false diff --no-renames --name-only -z "$merge_bases" "$tip" | tr '\0' '\n')" \
  || ai_fail "Could not list what the PR changes (git diff failed)."
history_paths="$(ai_git -c core.quotePath=false log --no-renames --name-only -z --format= \
                   --diff-merges=dense-combined "$base..$tip" "^$main_ref" | tr '\0' '\n')" \
  || ai_fail "Could not list the paths the AI's commits touched (git log failed)."
changed="$(printf '%s\n%s\n' "$effect_paths" "$history_paths" | { grep -v '^$' || true; } | sort -u)"
scratch="$(printf '%s\n' "$changed" | grep -E '(^|/)\.ai-(pr-body|comment|review)\.md$' || true)"
[[ -z "$scratch" ]] || ai_fail "AI scratch files were committed: $(printf '%s' "$scratch" | tr '\n' ' ')"
workflows="$(printf '%s\n' "$changed" | grep -c '^\.github/workflows/' || true)"
# The AI's own config and the push scripts: an approved plan for app code never
# approves changes to these, so ai-push.yml refuses them in every mode.
agent_config="$(printf '%s\n' "$changed" | grep -cE '^(\.claude/|CLAUDE\.md$|scripts/ai-push/)' || true)"
github_files="$(printf '%s\n' "$changed" | grep '^\.github/' || true)"
if [[ -n "$github_files" ]]; then
  ai_warn "This push changes files under .github/ ($workflows workflow file(s)): $(printf '%s\n' "$github_files" | head -20 | tr '\n' ' ')"
fi
high_risk=false; risky=""
if [[ -n "$labeler" ]]; then
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    while IFS= read -r g; do
      [[ -z "$g" ]] && continue
      if ai_path_matches "$p" "$g"; then risky="$risky $p"; break; fi
    done <<<"$globs"
  done <<<"$changed"
  [[ -z "$github_files" ]] || risky="$risky $(printf '%s' "$github_files" | tr '\n' ' ')"
  if [[ -n "${risky// /}" ]]; then high_risk=true; ai_warn "High-risk paths changed:$(printf '%s' "$risky" | cut -c1-500)"; fi
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
ai_output agent_config "$agent_config"
ai_output high_risk "$high_risk"
echo "OK: $commits commit(s) on $branch, tip $tip, high_risk=$high_risk."

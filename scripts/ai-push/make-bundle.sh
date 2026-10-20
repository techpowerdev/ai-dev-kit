#!/usr/bin/env bash
# Usage: make-bundle.sh --mode pipeline|pr|none --issue N --base SHA [--branch B] --out DIR [--repo DIR]
#
# Runs at the end of a Claude job (with `if: always()`), so commits Claude made are
# kept even if it stopped early. Everything written to DIR is UNTRUSTED: the trusted
# push job checks all of it again (inspect-bundle.sh).
#
#   pipeline  the one local branch ai/<N>-* (more than one = refused)
#   pr        refs/heads/<B> (the PR head branch)
#   none      not pushable (fork, non-ai branch, plain issue): only count commits so
#             the trusted job can explain why nothing was pushed
#
# Writes: status (empty|bundle|refused|none), branch, commits, ai.bundle,
# uncommitted.txt (working-tree changes, minus .ai-*.md), pr-body.md (copy of
# .ai-pr-body.md if it is a regular file of at most 60000 bytes).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

mode=""; issue=""; base=""; branch=""; out=""; repo=.
while (( $# )); do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$mode" =~ ^(pipeline|pr|none)$ && -n "$base" && -n "$out" ]] || { echo "usage: see header" >&2; exit 2; }
mkdir -p "$out"
cd "$repo"

write() { printf '%s\n' "$2" >"$out/$1"; }
write status empty; write branch ""; write commits 0

# Working-tree changes Claude did not commit (decision 6: warn, never commit them).
ai_git status --porcelain --untracked-files=all 2>/dev/null \
  | awk '{ p = substr($0, 4) } p !~ /(^|\/)\.ai-[^\/]*\.md$/ { print p }' >"$out/uncommitted.txt" || true

# PR body: a regular file only (no symlink), capped.
if [[ -f .ai-pr-body.md && ! -L .ai-pr-body.md ]] && (( $(wc -c <.ai-pr-body.md) <= 60000 )); then
  cp .ai-pr-body.md "$out/pr-body.md"
fi

case "$mode" in
  pipeline)
    candidates="$(ai_git for-each-ref --format='%(refname:short)' "refs/heads/ai/$issue-*")"
    count="$(printf '%s' "$candidates" | grep -c . || true)"
    if (( count == 0 )); then echo "No local ai/$issue-* branch: nothing to bundle."; exit 0; fi
    if (( count > 1 )); then write status refused; echo "More than one ai/$issue-* branch; refusing."; exit 0; fi
    branch="$candidates" ;;
  pr|none)
    [[ -n "$branch" ]] || { echo "--branch is required for mode $mode" >&2; exit 2; } ;;
esac

ai_git rev-parse --verify --quiet "refs/heads/$branch^{commit}" >/dev/null || { echo "Branch $branch does not exist locally: nothing to bundle."; exit 0; }
ai_git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { write status refused; echo "Base $base is not in this repo; refusing."; exit 0; }

commits="$(ai_git rev-list --count "$base..refs/heads/$branch")"
write branch "$branch"; write commits "$commits"
if (( commits == 0 )); then echo "No commits on $branch beyond the base."; exit 0; fi
if [[ "$mode" == none ]]; then write status none; echo "$commits commit(s) on $branch, but this run may not push."; exit 0; fi

ai_git bundle create "$out/ai.bundle" "refs/heads/$branch" "^$base" >/dev/null 2>&1
write status bundle
echo "Bundled $commits commit(s) from $branch."

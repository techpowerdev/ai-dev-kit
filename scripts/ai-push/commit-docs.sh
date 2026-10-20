#!/usr/bin/env bash
# Usage: commit-docs.sh --tip SHA --name <n>-<slug> --spec FILE --plan FILE [--repo DIR]
# Prints the SHA to push: a new commit on top of TIP, or TIP itself when the files
# are already there with the same content.
#
# Trusted. Adds docs/specs/<name>.md and docs/plans/<name>.md on top of Claude's
# commits using plumbing only: a temporary index, hash-object, update-index,
# write-tree and commit-tree. Claude's tree is never checked out, so its symlinks,
# hooks and attributes cannot do anything here.
# If Claude's commits already changed those paths, they are overwritten (warning).
# If docs/specs or docs/plans is a file or symlink in TIP, it fails.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

tip=""; name=""; spec=""; plan=""; repo=.
while (( $# )); do
  case "$1" in
    --tip) tip="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --spec) spec="$2"; shift 2 ;;
    --plan) plan="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$tip" =~ ^[0-9a-f]{40}$ ]] || ai_fail "--tip must be a full commit SHA."
[[ "$name" =~ ^[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$ && ${#name} -le 100 ]] || ai_fail "--name must look like 12-some-slug."
for f in "$spec" "$plan"; do
  [[ -f "$f" && ! -L "$f" ]] || ai_fail "Doc file '$f' is missing or a symlink."
done
spec="$(cd "$(dirname "$spec")" && pwd)/$(basename "$spec")"
plan="$(cd "$(dirname "$plan")" && pwd)/$(basename "$plan")"
cd "$repo"
ai_git rev-parse --verify --quiet "$tip^{commit}" >/dev/null || ai_fail "The tip commit is not in this repo."
issue="${name%%-*}"

for dir in docs docs/specs docs/plans; do
  mode="$(ai_git ls-tree "$tip" -- "$dir" | awk '{print $1}')"
  [[ -z "$mode" || "$mode" == 040000 ]] || ai_fail "'$dir' in the pushed commits is not a directory (mode $mode)."
done

index="$(mktemp)"; trap 'rm -f "$index"' EXIT
rm -f "$index"
export GIT_INDEX_FILE="$index"
ai_git read-tree "$tip"
for pair in "specs:$spec" "plans:$plan"; do
  kind="${pair%%:*}"; file="${pair#*:}"; path="docs/$kind/$name.md"
  blob="$(ai_git hash-object -w --no-filters -- "$file")"
  existing="$(ai_git ls-tree "$tip" -- "$path" | awk '{print $1" "$3}')"
  [[ "$existing" != 040000* ]] || ai_fail "$path is a directory in the pushed commits."
  if [[ -n "$existing" && "$existing" != "100644 $blob" ]]; then
    # stderr: stdout carries only the SHA (the runner reads workflow commands from both)
    ai_warn "The pushed commits already had $path; it is replaced by the approved version from #$issue." >&2
  fi
  ai_git update-index --add --cacheinfo "100644,$blob,$path"
done
tree="$(ai_git write-tree)"
unset GIT_INDEX_FILE

if [[ "$tree" == "$(ai_git rev-parse "$tip^{tree}")" ]]; then
  echo "$tip"
  exit 0
fi
GIT_AUTHOR_NAME="github-actions[bot]" GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com" \
GIT_COMMITTER_NAME="github-actions[bot]" GIT_COMMITTER_EMAIL="41898282+github-actions[bot]@users.noreply.github.com" \
  ai_git commit-tree "$tree" -p "$tip" -m "docs: save approved spec and plan for #$issue"

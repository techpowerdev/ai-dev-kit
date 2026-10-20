#!/usr/bin/env bash
# Usage: open-pr.sh --branch B --base DEFAULT --issue N --range BASE..TIP --footer FILE
#          [--body-in FILE] [--repo DIR] [--slug OWNER/REPO]
# Env: GH_TOKEN (the push token, so the PR triggers CI), GITHUB_REPOSITORY (or --slug)
#
# Trusted. Opens the PR for a pushed ai/* branch, or does nothing if one is open.
#   - body: Claude's PR body (UNTRUSTED text) if it is a regular file, not a symlink,
#     at most 60000 bytes; otherwise the PR template plus a warning
#   - then the footer the trusted job wrote (paths, commits, workflow files): the
#     part a reviewer can rely on
#   - title: subject of Claude's first commit, control characters removed, at most
#     100 characters; "AI: #N" if there is none
#   - never a draft (AI review skips drafts)
# Output (GITHUB_OUTPUT): pr_url
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

branch=""; base=""; issue=""; range=""; footer=""; body_in=""; repo=.; slug="${GITHUB_REPOSITORY:-}"
while (( $# )); do
  case "$1" in
    --branch) branch="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --range) range="$2"; shift 2 ;;
    --footer) footer="$2"; shift 2 ;;
    --body-in) body_in="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --slug) slug="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
ai_validate_branch "$branch" || ai_fail "Refusing to open a PR from '$branch'."
[[ "$issue" =~ ^[0-9]+$ && "$base" =~ ^[A-Za-z0-9._/-]+$ && -n "$slug" ]] || { echo "usage: see header" >&2; exit 2; }
[[ "$range" =~ ^[0-9a-f]{40}\.\.[0-9a-f]{40}$ ]] || ai_fail "--range must be BASE..TIP with full SHAs."
[[ -f "$footer" && ! -L "$footer" ]] || ai_fail "Footer file missing."

existing="$(gh pr list --repo "$slug" --head "$branch" --state open --json url | jq -r '.[0].url // empty')"
if [[ -n "$existing" ]]; then
  echo "A PR is already open for $branch: $existing"
  ai_output pr_url "$existing"
  exit 0
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
body="$work/body.md"
if [[ -n "$body_in" && -f "$body_in" && ! -L "$body_in" ]] && (( $(wc -c <"$body_in") <= 60000 )); then
  cat "$body_in" >"$body"
else
  ai_warn "Claude's PR body is missing, a symlink or too large; using the PR template."
  {
    echo "> ⚠️ The AI did not provide a usable PR description. Fill this in before review."
    echo
    if [[ -f "$repo/.github/pull_request_template.md" ]]; then cat "$repo/.github/pull_request_template.md"; fi
  } >"$body"
fi
grep -qE "(Closes|Fixes|Resolves) #$issue([^0-9]|$)" "$body" || printf '\nCloses #%s\n' "$issue" >>"$body"
{ echo; echo "---"; cat "$footer"; } >>"$body"

subject="$(ai_git -C "$repo" log --reverse --format=%s "$range" | head -n 1)"
title="$(printf '%s' "$subject" | LC_ALL=C tr -d '\000-\037\177' | cut -c1-100)"
[[ -n "$title" ]] || title="AI: #$issue"

url="$(gh pr create --repo "$slug" --base "$base" --head "$branch" --title "$title" --body-file "$body")"
echo "Opened $url"
ai_output pr_url "$url"

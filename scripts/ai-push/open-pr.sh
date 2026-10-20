#!/usr/bin/env bash
# Usage: open-pr.sh --branch B --base DEFAULT --issue N --range BASE..TIP --footer FILE
#          [--body-in FILE] [--repo DIR] [--slug OWNER/REPO]
# Env: GH_TOKEN (the push token, so the PR triggers CI), GITHUB_REPOSITORY (or --slug)
#
# Trusted. Opens the PR for a pushed ai/* branch, or does nothing if one is open.
#   - the TRUSTED part comes first: "Closes #N" and the footer the trusted job wrote
#     (paths, commits, workflow files), so Claude's text cannot hide or fake it
#   - then Claude's PR body (UNTRUSTED) if it is a regular file, not a symlink, at most
#     60000 bytes, with HTML comments opened ("<!--" shown as text) and every closing
#     keyword that points at an issue turned into "Refs" (#N, owner/repo#N and issue
#     or pull URLs), so only the trusted "Closes #N" closes anything; otherwise the
#     PR template plus a warning
#   - closing keywords in Claude's commit messages (a squash merge can copy them to
#     the default branch) are listed as a warning in the trusted part
#   - title: subject of Claude's first commit, control and bidi characters removed,
#     at most 100 characters (not bytes); "AI: #N" if there is none
#   - an open PR from this repo's branch is reused; fork PRs with the same branch
#     name are ignored
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

existing="$(gh pr list --repo "$slug" --head "$branch" --state open --json url,isCrossRepository \
  | jq -r '[.[] | select(.isCrossRepository == false)][0].url // empty')"
if [[ -n "$existing" ]]; then
  echo "A PR is already open for $branch: $existing"
  ai_output pr_url "$existing"
  exit 0
fi

export AI_ISSUE="$issue"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
body="$work/body.md"
commit_closers="$(ai_git -C "$repo" log --format=%B "$range" \
  | grep -oiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' \
  | sort -u | head -n 20 || true)"
{
  echo "Closes #$issue"
  echo
  echo "<!-- trusted: written by the AI push job, not by the AI -->"
  cat "$footer"
  if [[ -n "$commit_closers" ]]; then
    echo
    echo "> ⚠️ Commit messages contain closing keywords; a squash merge may close these issues: $(printf '%s' "$commit_closers" | tr '\n' ',' | sed 's/,$//')"
  fi
  echo
  echo "---"
  echo
} >"$body"
if [[ -n "$body_in" && -f "$body_in" && ! -L "$body_in" ]] && (( $(wc -c <"$body_in") <= 60000 )); then
  # Untrusted: show HTML comments as text, and turn every closing keyword that points
  # at an issue into "Refs" ("Fixes o/r#34" -> "Refs o/r#34"); GitHub does not close
  # anything on "Refs". The trusted "Closes #N" above is the only closing reference.
  perl -pe '
    s/<!--/&lt;!--/g;
    s{\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)(\s*:?\s+)(?=(?:[\w.-]+/[\w.-]+)?#\d+|https?://github\.com/[\w.-]+/[\w.-]+/(?:issues|pull)/\d+)}{Refs$1}gi;
  ' "$body_in" >>"$body"
else
  ai_warn "Claude's PR body is missing, a symlink or too large; using the PR template."
  {
    echo "> ⚠️ The AI did not provide a usable PR description. Fill this in before review."
    echo
    if [[ -f "$repo/.github/pull_request_template.md" ]]; then cat "$repo/.github/pull_request_template.md"; fi
  } >>"$body"
fi

subject="$(ai_git -C "$repo" log --reverse --format=%s "$range" | awk 'NR == 1')"
title="$(printf '%s' "$subject" | perl -CSD -ne 'chomp; s/[\x{0}-\x{1f}\x{7f}-\x{9f}\x{200e}\x{200f}\x{202a}-\x{202e}\x{2066}-\x{2069}]//g; print substr($_, 0, 100)')"
[[ -n "$title" ]] || title="AI: #$issue"

url="$(gh pr create --repo "$slug" --base "$base" --head "$branch" --title "$title" --body-file "$body")"
echo "Opened $url"
ai_output pr_url "$url"

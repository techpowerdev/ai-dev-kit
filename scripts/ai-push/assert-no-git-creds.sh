#!/usr/bin/env bash
# Usage: assert-no-git-creds.sh [--warn-only] [--repo DIR]
#
# Runs in a Claude job, before Claude (must pass) and after it (--warn-only, to see
# whether claude-code-action wrote its own auth). Fails if git in DIR could push
# without being given a token: an http extraheader, an includeIf (actions/checkout
# v6+ links its credentials file that way), a credential helper, a remote URL with
# user info, a url.*.insteadOf rewrite (can carry user info), core.askpass, or a
# git-credentials-* file in RUNNER_TEMP. Prints key names only,
# never values.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

warn_only=false; repo=.
while (( $# )); do
  case "$1" in
    --warn-only) warn_only=true; shift ;;
    --repo) repo="${2:?--repo needs a value}"; shift 2 ;;
    *) echo "usage: assert-no-git-creds.sh [--warn-only] [--repo DIR]" >&2; exit 2 ;;
  esac
done

found=()
while IFS= read -r key; do
  [[ -n "$key" ]] && found+=("git config: $(ai_redact_userinfo "$key")")
done < <(git -C "$repo" config --name-only --get-regexp '^(http\..*extraheader|include(if)?\..*|credential\..*|url\..*|core\.askpass|core\.sshcommand)$' 2>/dev/null || true)

while IFS= read -r line; do
  name="${line%%[[:space:]]*}"
  url="$(printf '%s' "$line" | awk '{print $2}')"
  if [[ "$url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://[^/@]+@ ]]; then found+=("remote '$name' URL has user info")
  elif [[ ! "$url" =~ ^https:// && ! "$url" =~ ^/ && ! "$url" =~ ^file:// ]]; then found+=("remote '$name' is not https (ssh keys or agents could push)"); fi
done < <(git -C "$repo" remote -v 2>/dev/null | sort -u || true)

for v in GIT_ASKPASS SSH_ASKPASS SSH_AUTH_SOCK; do
  [[ -n "${!v:-}" ]] && found+=("environment variable $v is set")
done

if [[ -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" ]]; then
  for f in "$RUNNER_TEMP"/git-credentials-*; do
    [[ -e "$f" ]] && found+=("credentials file in RUNNER_TEMP: $(basename "$f")")
  done
fi

if (( ${#found[@]} == 0 )); then
  echo "No git credentials found in $repo."
  exit 0
fi

for f in "${found[@]}"; do
  if $warn_only; then ai_warn "git credential present: $f"; else echo "::error title=ai-push::$(ai_sanitize "git credential present: $f")"; fi
done
$warn_only && exit 0
exit 1

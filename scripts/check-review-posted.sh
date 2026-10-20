#!/usr/bin/env bash
# Usage: check-review-posted.sh <pr-number> <started-at, e.g. 2026-10-20T08:35:09Z>
# Env: GH_TOKEN, GITHUB_REPOSITORY
#
# A Claude run can end "successfully" without posting (for example when it stops
# while subagents are still working). This fails unless a bot comment or review
# starting with "## AI Review" was posted on the PR after the job started.
# Human comments and other bots' comments do not count.
set -euo pipefail
pr="${1:?usage: check-review-posted.sh <pr-number> <started-at>}"
since="${2:?usage: check-review-posted.sh <pr-number> <started-at>}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
marker='## AI Review'

count_since() {  # count_since <api-path> <timestamp-field>
  gh api "$1" --paginate \
    | jq -s --arg since "$since" --arg m "$marker" --arg f "$2" '
        [ .[] | if type == "array" then .[] else . end
          | select(.user.type == "Bot" and (.[$f] // "") >= $since
                   and ((.body // "") | ltrimstr("\n") | startswith($m))) ] | length'
}

comments="$(count_since "repos/$repo/issues/$pr/comments" created_at)"
reviews="$(count_since "repos/$repo/pulls/$pr/reviews" submitted_at)"

if (( comments + reviews == 0 )); then
  echo "::error title=AI review not posted::Claude finished but posted no '$marker' comment or review on PR #$pr."
  exit 1
fi
echo "AI review posted on PR #$pr ($comments comment(s), $reviews review(s))."

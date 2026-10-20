#!/usr/bin/env bash
# Usage: fetch-approved-docs.sh --issue N --stage spec|plan --bot LOGIN --out FILE
#          (--approved-by-label LABEL | --after-label LABEL) [--repo OWNER/REPO]
# Env: GH_TOKEN (read access is enough), GITHUB_REPOSITORY (if --repo is not given)
#
# Trusted. Picks the spec or plan comment that a human approved and writes it, with
# the owner's answers, to FILE so the push job can commit it as docs/specs|plans.
#
# T = time of the latest "labeled" event for LABEL whose actor is not a bot.
# The doc is the bot's comment whose first non-empty line starts with "# Spec:" or
# "# Plan:" (amendment A2):
#   --approved-by-label  the latest such comment created BEFORE T; fails if it was
#                        edited after T (changed after approval)
#   --after-label        the EARLIEST such comment created after T: the plan that
#                        plan-and-build posts right after approved:spec (not approved
#                        by a human yet, the header says so). Later "# Plan:" comments,
#                        e.g. from an @claude run, are not picked up.
# Approval counts only if: the labeler is a person (not a bot, not null) with write,
# maintain or admin permission on the repo, and the label was not removed after T.
# Answers (approved mode): comments by people with write+ permission, not bots,
# created after the doc and at or before T. An answer edited after T fails, like the
# doc (the text must be what the approver saw).
# --bot must be the Claude app's login; github-actions[bot] is refused because any
# workflow with GITHUB_TOKEN can post as it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

issue=""; stage=""; bot=""; out=""; label=""; how=""; repo="${GITHUB_REPOSITORY:-}"
while (( $# )); do
  case "$1" in
    --issue) issue="$2"; shift 2 ;;
    --stage) stage="$2"; shift 2 ;;
    --bot) bot="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --approved-by-label) how=approved; label="$2"; shift 2 ;;
    --after-label) how=after; label="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$issue" =~ ^[0-9]+$ && "$stage" =~ ^(spec|plan)$ && -n "$bot" && -n "$out" && -n "$how" && -n "$repo" ]] \
  || { echo "usage: see header" >&2; exit 2; }
[[ "$bot" != "github-actions[bot]" ]] || ai_fail "--bot must be the Claude app's login, not github-actions[bot]."

# can_write <login> — 0 if the user has write, maintain or admin on the repo.
can_write() {
  local perm
  perm="$(gh api "repos/$repo/collaborators/$1/permission" --jq .permission 2>/dev/null || true)"
  [[ "$perm" =~ ^(admin|maintain|write)$ ]]
}
case "$stage" in spec) heading='# Spec:' ;; plan) heading='# Plan:' ;; esac

events="$(gh api "repos/$repo/issues/$issue/events" --paginate | jq -s '[.[] | if type == "array" then .[] else . end]')"
comments="$(gh api "repos/$repo/issues/$issue/comments" --paginate | jq -s '[.[] | if type == "array" then .[] else . end]')"

approval="$(jq -c --arg l "$label" '
  [ .[] | select(.event == "labeled" and .label.name == $l
                 and (.actor.login // "") != "" and (.actor.type // "") != "Bot") ]
  | sort_by(.created_at) | last // empty' <<<"$events")"
[[ -n "$approval" ]] || ai_fail "No human added the label '$label' to #$issue."
T="$(jq -r '.created_at' <<<"$approval")"
approver="$(jq -r '.actor.login' <<<"$approval")"
removed="$(jq -r --arg l "$label" --arg t "$T" '
  [ .[] | select(.event == "unlabeled" and .label.name == $l and .created_at >= $t) ] | length' <<<"$events")"
(( removed == 0 )) || ai_fail "The label '$label' was removed after it was added: approval withdrawn."
can_write "$approver" || ai_fail "@$approver added '$label' but does not have write access: not an approval."

# shellcheck disable=SC2016  # $bot and $h are jq variables, not shell
# Doc before T: created strictly before the label. Answers: up to and including T.
is_doc='(.user.login == $bot) and ((.body // "") | sub("^[\\s]+"; "") | startswith($h))'
if [[ "$how" == approved ]]; then
  doc="$(jq -c --arg bot "$bot" --arg h "$heading" --arg t "$T" \
    "[ .[] | select($is_doc and .created_at < \$t) ] | sort_by(.created_at) | last // empty" <<<"$comments")"
else
  doc="$(jq -c --arg bot "$bot" --arg h "$heading" --arg t "$T" \
    "[ .[] | select($is_doc and .created_at > \$t) ] | sort_by(.created_at) | first // empty" <<<"$comments")"
fi
[[ -n "$doc" ]] || ai_fail "No '$heading' comment by $bot $( [[ $how == approved ]] && echo before || echo after ) '$label' on #$issue."

doc_created="$(jq -r '.created_at' <<<"$doc")"
doc_updated="$(jq -r '.updated_at // .created_at' <<<"$doc")"
if [[ "$how" == approved && "$doc_updated" > "$T" ]]; then
  ai_fail "The approved $stage comment was edited after '$label' was added ($doc_updated > $T). Re-apply the label to approve the new text."
fi

answers=""
if [[ "$how" == approved ]]; then
  while IFS= read -r a; do
    [[ -z "$a" ]] && continue
    login="$(jq -r '.user.login' <<<"$a")"
    can_write "$login" || continue
    if [[ "$(jq -r '.updated_at // .created_at' <<<"$a")" > "$T" ]]; then
      ai_fail "An answer by @$login was edited after '$label' was added. Re-apply the label to approve the new text."
    fi
    answers="$answers$(jq -r '"### @\(.user.login) — \(.created_at)\n\n\(.body)\n\n"' <<<"$a")"
  done < <(jq -c --arg from "$doc_created" --arg t "$T" '
    [ .[] | select((.user.type // "") != "Bot" and .created_at > $from and .created_at <= $t) ]
    | sort_by(.created_at) | .[]' <<<"$comments")
fi

{
  echo "<!-- Saved by the AI push job from issue #$issue. Do not edit by hand; change the issue and re-approve. -->"
  echo "> Source: $(jq -r '.html_url' <<<"$doc")"
  if [[ "$how" == approved ]]; then
    echo "> Approved: label \`$label\` added by @$approver at $T"
  else
    echo "> Written after label \`$label\` (added by @$approver at $T); not separately approved"
  fi
  echo
  jq -r '.body' <<<"$doc"
  if [[ -n "$answers" ]]; then
    echo
    echo "## คำตอบจากเจ้าของใน issue"
    echo
    printf '%s\n' "$answers"
  fi
} >"$out"
echo "Saved the $stage of #$issue ($(wc -c <"$out" | tr -d ' ') bytes)."

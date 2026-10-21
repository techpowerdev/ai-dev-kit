#!/usr/bin/env bash
# Tests scripts/ai-push/{fetch-approved-docs,commit-docs,open-pr,refuse-push}.sh
# with a fake gh (canned issue events/comments) and real git repos.
# shellcheck disable=SC2015  # "cond && ok || bad" is safe here: ok and bad always succeed
set -euo pipefail
cd "$(dirname "$0")/../.."
kit="$PWD"
S="$kit/scripts/ai-push"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GITHUB_OUTPUT 2>/dev/null || true
export PATH="$kit/tests/kit/fake-gh:$PATH" GITHUB_REPOSITORY=o/r

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "   ✗ $1"; }
expect_ok()   { local d="$1"; shift; if "$@" >"$tmp/last.out" 2>"$tmp/last.err"; then ok; else bad "$d"; tail -3 "$tmp/last.out" "$tmp/last.err" | sed 's/^/       /'; fi; }
expect_fail() { local d="$1"; shift; if "$@" >"$tmp/last.out" 2>"$tmp/last.err"; then bad "$d (expected failure)"; else ok; fi; }
# why <description> <text> — the last failure's message contains text
why() { if grep -qF -- "$2" "$tmp/last.out" "$tmp/last.err"; then ok; else bad "$1: failure message lacks '$2'"; fi; }
has()   { if grep -qF -- "$3" "$2"; then ok; else bad "$1: expected '$3'"; fi; }
lacks() { if grep -qF -- "$3" "$2"; then bad "$1: did not expect '$3'"; else ok; fi; }

# ---------------------------------------------------------------- fixtures
R="$tmp/resp"; mkdir -p "$R"; export FAKE_GH_RESPONSES="$R" FAKE_GH_LOG="$tmp/gh.log"
echo read >"$R/perm-rando"   # a drive-by user: read access only (the fake defaults to write)
bot='"user":{"login":"claude[bot]","type":"Bot"},"author_association":"NONE"'
owner='"user":{"login":"boss","type":"User"},"author_association":"OWNER"'
member='"user":{"login":"mate","type":"User"},"author_association":"MEMBER"'
collab='"user":{"login":"helper","type":"User"},"author_association":"COLLABORATOR"'
reader='"user":{"login":"reader","type":"User"},"author_association":"MEMBER"'
rando='"user":{"login":"rando","type":"User"},"author_association":"NONE"'
c() {  # c <id> <who-json> <created> <body> [updated]
  printf '{"id":%s,"html_url":"https://github.com/o/r/issues/12#issuecomment-%s",%s,"created_at":"%s","updated_at":"%s","body":%s}' \
    "$1" "$1" "$2" "$3" "${5:-$3}" "$(jq -Rn --arg b "$4" '$b')"
}
ev() {  # ev <label> <actor-type> <created> [actor-login]
  printf '{"event":"labeled","label":{"name":"%s"},"actor":{"login":"%s","type":"%s"},"created_at":"%s"}' \
    "$1" "${4:-$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')}" "$2" "$3"
}
fetch() { bash "$S/fetch-approved-docs.sh" --issue 12 --bot 'claude[bot]' --out "$tmp/doc.md" "$@"; }

SPEC="$(c 1 "$bot" 2026-10-20T10:00:00Z $'# Spec: Do the thing\n\nAC1 ...')"
ANS1="$(c 2 "$owner" 2026-10-20T10:30:00Z 'Answer from the owner')"
ANS2="$(c 3 "$member" 2026-10-20T10:40:00Z 'Answer from a member')"
NOISE="$(c 4 "$rando" 2026-10-20T10:45:00Z 'Drive-by comment')"
FAKESPEC="$(c 5 "$rando" 2026-10-20T10:50:00Z $'# Spec: a human pretending')"
BOTNOTE="$(c 6 "$bot" 2026-10-20T10:55:00Z 'Bot progress note')"
LATESPEC="$(c 7 "$bot" 2026-10-20T12:00:00Z $'# Spec: posted after approval')"
LATEANS="$(c 8 "$owner" 2026-10-20T12:10:00Z 'Answer after approval')"
printf '[%s,%s,%s,%s,%s,%s,%s,%s]' "$SPEC" "$ANS1" "$ANS2" "$NOISE" "$FAKESPEC" "$BOTNOTE" "$LATESPEC" "$LATEANS" >"$R/comments.json"
printf '[%s,%s]' "$(ev approved:spec User 2026-10-20T09:00:00Z)" "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"

# ---------------------------------------------------------------- fetch: approved spec
expect_ok "fetch the approved spec" fetch --stage spec --approved-by-label approved:spec
has   "spec body"                       "$tmp/doc.md" "AC1 ..."
has   "source link"                     "$tmp/doc.md" "issuecomment-1"
has   "approval line uses the latest label event" "$tmp/doc.md" "at 2026-10-20T11:00:00Z"
lacks "spec posted after approval ignored" "$tmp/doc.md" "posted after approval"
lacks "a human's '# Spec:' comment is not the doc" "$tmp/doc.md" "a human pretending"
has   "owner answer included"           "$tmp/doc.md" "Answer from the owner"
has   "member answer included"          "$tmp/doc.md" "Answer from a member"
lacks "NONE association excluded"       "$tmp/doc.md" "Drive-by comment"
lacks "bot comments are not answers"    "$tmp/doc.md" "Bot progress note"
lacks "answers after approval excluded" "$tmp/doc.md" "Answer after approval"
has   "answers section"                 "$tmp/doc.md" "## คำตอบจากเจ้าของใน issue"

# edited after approval
printf '[%s,%s]' "$(c 1 "$bot" 2026-10-20T10:00:00Z $'# Spec: X' 2026-10-20T11:30:00Z)" "$ANS1" >"$R/comments.json"
expect_fail "a spec edited after approval fails" fetch --stage spec --approved-by-label approved:spec
# label only added by a bot
printf '[%s,%s]' "$SPEC" "$ANS1" >"$R/comments.json"
printf '[%s]' "$(ev approved:spec Bot 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_fail "a label added only by a bot does not count" fetch --stage spec --approved-by-label approved:spec
# no doc at all
printf '[%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
printf '[%s]' "$ANS1" >"$R/comments.json"
expect_fail "no spec comment fails" fetch --stage spec --approved-by-label approved:spec

# ---------------------------------------------------------------- fetch: plans
PLAN_LOW="$(c 20 "$bot" 2026-10-20T11:05:00Z $'# Plan: steps\n\n1. one')"
printf '[%s,%s,%s]' "$SPEC" "$ANS1" "$PLAN_LOW" >"$R/comments.json"
printf '[%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_ok "fetch the plan written after approved:spec" fetch --stage plan --after-label approved:spec
has   "plan body"                        "$tmp/doc.md" "1. one"
has   "header says not separately approved" "$tmp/doc.md" "not separately approved"
lacks "no answers section for after-label" "$tmp/doc.md" "คำตอบจากเจ้าของ"
printf '[%s,%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" "$(ev approved:plan User 2026-10-20T13:00:00Z)" >"$R/events.json"
expect_fail "after-label with no plan after the label fails" fetch --stage plan --after-label approved:plan
why "it fails for the missing plan" "No '# Plan:' comment"
printf '[%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"

LATER_PLAN="$(c 22 "$bot" 2026-10-20T11:40:00Z $'# Plan: injected later by another run')"
printf '[%s,%s,%s,%s]' "$SPEC" "$ANS1" "$PLAN_LOW" "$LATER_PLAN" >"$R/comments.json"
expect_ok "after-label with two plans" fetch --stage plan --after-label approved:spec
has   "the earliest plan after the label is used" "$tmp/doc.md" "1. one"
lacks "a later plan is not used"                  "$tmp/doc.md" "injected later"
PLAN_ANS="$(c 21 "$owner" 2026-10-20T11:30:00Z 'Decision answers')"
printf '[%s,%s,%s,%s]' "$SPEC" "$ANS1" "$PLAN_LOW" "$PLAN_ANS" >"$R/comments.json"
printf '[%s,%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" "$(ev approved:plan User 2026-10-20T12:00:00Z)" >"$R/events.json"
expect_ok "fetch the plan approved by approved:plan" fetch --stage plan --approved-by-label approved:plan
has   "plan answers included"            "$tmp/doc.md" "Decision answers"
lacks "spec answers not mixed into the plan" "$tmp/doc.md" "Answer from the owner"

# ---------------------------------------------------------------- fetch: review round
printf '[%s,%s]' "$SPEC" "$ANS1" >"$R/comments.json"
# label removed after it was added
printf '[%s,{"event":"unlabeled","label":{"name":"approved:spec"},"actor":{"login":"user","type":"User"},"created_at":"2026-10-20T11:10:00Z"}]' \
  "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_fail "approval withdrawn by removing the label" fetch --stage spec --approved-by-label approved:spec
why "says it was withdrawn" "approval withdrawn"
# null actor
printf '[{"event":"labeled","label":{"name":"approved:spec"},"actor":null,"created_at":"2026-10-20T11:00:00Z"}]' >"$R/events.json"
expect_fail "a labeled event without an actor does not count" fetch --stage spec --approved-by-label approved:spec
# labeler without write access
printf '[%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
echo triage >"$R/perm-user"
expect_fail "a triage-only labeler is not an approval" fetch --stage spec --approved-by-label approved:spec
why "names the permission problem" "does not have write access"
rm -f "$R/perm-user"
# answers: write+ only, collaborators included, read-only members excluded, edits after T fail
echo read >"$R/perm-reader"
printf '[%s,%s,%s]' "$SPEC" "$(c 30 "$collab" 2026-10-20T10:20:00Z 'Collaborator answer')" "$(c 31 "$reader" 2026-10-20T10:25:00Z 'Read-only member text')" >"$R/comments.json"
expect_ok "fetch with collaborator and read-only answers" fetch --stage spec --approved-by-label approved:spec
has   "collaborator answer included"     "$tmp/doc.md" "Collaborator answer"
lacks "read-only member excluded"        "$tmp/doc.md" "Read-only member text"
rm -f "$R/perm-reader"
printf '[%s,%s]' "$SPEC" "$(c 32 "$owner" 2026-10-20T10:30:00Z 'Edited answer' 2026-10-20T11:20:00Z)" >"$R/comments.json"
expect_fail "an answer edited after approval fails" fetch --stage spec --approved-by-label approved:spec
why "names the edited answer" "was edited after"
# github-actions[bot] as --bot is refused
expect_fail "github-actions[bot] is refused as the doc author" bash "$S/fetch-approved-docs.sh" --issue 12 --bot 'github-actions[bot]' --out "$tmp/doc.md" --stage spec --approved-by-label approved:spec
# paginated responses (one array per page) are merged
printf '[%s][%s]' "$SPEC" "$ANS1" >"$R/comments.json"
expect_ok "paginated comments are merged" fetch --stage spec --approved-by-label approved:spec
has "answer from page 2" "$tmp/doc.md" "Answer from the owner"

# ---------------------------------------------------------------- 3a: fetch hardening
printf '[%s,%s]' "$SPEC" "$ANS1" >"$R/comments.json"
printf '[%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
echo __ERROR__ >"$R/perm-user"
expect_fail "a permission API error fails instead of meaning 'no write'" fetch --stage spec --approved-by-label approved:spec
why "says it could not read the permission" "Could not read the repo permission"
rm -f "$R/perm-user"; echo __ERROR__ >"$R/perm-boss"
expect_fail "an API error on an answer author fails too" fetch --stage spec --approved-by-label approved:spec
rm -f "$R/perm-boss"
# two bot specs in the window between ai:spec and approved:spec is ambiguous
SPEC_B="$(c 40 "$bot" 2026-10-20T10:15:00Z $'# Spec: second version from another run')"
printf '[%s,%s,%s]' "$SPEC" "$SPEC_B" "$ANS1" >"$R/comments.json"
printf '[%s,%s]' "$(ev ai:spec User 2026-10-20T09:50:00Z)" "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_fail "two bot specs in the window fail as ambiguous" fetch --stage spec --approved-by-label approved:spec --window-label ai:spec
why "says ambiguous" "ambiguous"
# re-running the spec (a new ai:spec label) resets the window
printf '[%s,%s,%s]' "$(ev ai:spec User 2026-10-20T09:50:00Z)" "$(ev ai:spec User 2026-10-20T10:10:00Z)" "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_ok "after re-running the spec, the newest one is used" fetch --stage spec --approved-by-label approved:spec --window-label ai:spec
has "the re-run spec is saved" "$tmp/doc.md" "second version from another run"
# no doc in the window: the latest one is from an earlier round (stale), even though
# it is the latest before T; only the window check refuses it
printf '[%s,%s]' "$SPEC" "$ANS1" >"$R/comments.json"
printf '[%s,%s]' "$(ev ai:spec User 2026-10-20T10:20:00Z)" "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_ok   "without a window the stale spec would be taken" fetch --stage spec --approved-by-label approved:spec
expect_fail "with the window, a spec from before it is stale" fetch --stage spec --approved-by-label approved:spec --window-label ai:spec
why "says it is from an earlier round" "earlier round"
# the plan case from the review: approved:spec re-applied after the plan, then approved:plan
PLAN_OLD="$(c 50 "$bot" 2026-10-20T10:30:00Z $'# Plan: written for the first spec')"
printf '[%s,%s]' "$SPEC" "$PLAN_OLD" >"$R/comments.json"
printf '[%s,%s,%s]' "$(ev approved:spec User 2026-10-20T10:10:00Z)" "$(ev approved:spec User 2026-10-20T10:40:00Z)" "$(ev approved:plan User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_fail "a plan from before a re-approved spec is not approved" fetch --stage plan --approved-by-label approved:plan --window-label approved:spec
why "says the plan is from an earlier round" "earlier round"
# no window label at all
printf '[%s,%s]' "$SPEC" "$ANS1" >"$R/comments.json"
printf '[%s]' "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
expect_fail "no window label event fails" fetch --stage spec --approved-by-label approved:spec --window-label ai:spec
why "says there is no window" "no window"
# the window label added by someone without write access does not count
printf '[%s,%s]' "$(ev ai:spec User 2026-10-20T09:50:00Z triager)" "$(ev approved:spec User 2026-10-20T11:00:00Z)" >"$R/events.json"
echo triage >"$R/perm-triager"
expect_fail "a window opened by a triager does not count" fetch --stage spec --approved-by-label approved:spec --window-label ai:spec
why "says no write access" "does not have write access"
rm -f "$R/perm-triager"
expect_ok "the same window opened by a writer works" fetch --stage spec --approved-by-label approved:spec --window-label ai:spec
# --window-label is only for approved mode
expect_fail "--window-label with --after-label is a usage error" fetch --stage plan --after-label approved:spec --window-label ai:spec
why "says it is only for approved mode" "only with --approved-by-label"

# ---------------------------------------------------------------- commit-docs
g() { git -C "$1" "${@:2}"; }
git init -q -b main "$tmp/repo"; echo a >"$tmp/repo/a.txt"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm base
echo b >"$tmp/repo/b.txt"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm "feat: claude work"
TIP="$(g "$tmp/repo" rev-parse HEAD)"
printf '# Spec: x\n' >"$tmp/spec.md"; printf '# Plan: y\n' >"$tmp/plan.md"
cd_docs() { bash "$S/commit-docs.sh" --repo "$tmp/repo" --name 12-do-thing --spec "$tmp/spec.md" --plan "$tmp/plan.md" "$@"; }
NEW="$(cd_docs --tip "$TIP")"
[[ "$NEW" =~ ^[0-9a-f]{40}$ && "$NEW" != "$TIP" ]] && ok || bad "commit-docs prints a new SHA"
[[ "$(g "$tmp/repo" rev-parse "$NEW^")" == "$TIP" ]] && ok || bad "the new commit's parent is Claude's tip"
[[ "$(g "$tmp/repo" show "$NEW:docs/specs/12-do-thing.md")" == "# Spec: x" && "$(g "$tmp/repo" show "$NEW:docs/plans/12-do-thing.md")" == "# Plan: y" ]] && ok || bad "both files at the right paths"
[[ "$(g "$tmp/repo" diff --name-only "$TIP" "$NEW" | tr '\n' ' ')" == "docs/plans/12-do-thing.md docs/specs/12-do-thing.md " ]] && ok || bad "only the two doc files change"
[[ "$(g "$tmp/repo" log -1 --format='%an|%s' "$NEW")" == "github-actions[bot]|docs: save approved spec and plan for #12" ]] && ok || bad "author and message"
[[ "$(g "$tmp/repo" rev-parse HEAD)" == "$TIP" && -z "$(g "$tmp/repo" status --porcelain)" ]] && ok || bad "the work tree and HEAD are untouched"
[[ "$(cd_docs --tip "$NEW")" == "$NEW" ]] && ok || bad "same content again: no new commit"
# Claude wrote the same path: overwritten with a warning, stdout stays a SHA
mkdir -p "$tmp/repo/docs/specs"; echo "claude's own" >"$tmp/repo/docs/specs/12-do-thing.md"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm own
TIP2="$(g "$tmp/repo" rev-parse HEAD)"
NEW2="$(cd_docs --tip "$TIP2" 2>"$tmp/warn.txt")"
[[ "$NEW2" =~ ^[0-9a-f]{40}$ ]] && ok || bad "stdout is only the SHA when warning"
[[ "$(g "$tmp/repo" show "$NEW2:docs/specs/12-do-thing.md")" == "# Spec: x" ]] && ok || bad "Claude's version is replaced"
has "overwrite is warned about" "$tmp/warn.txt" "replaced by the approved version"
# docs/specs as a file, docs as a symlink
g "$tmp/repo" rm -qr docs; printf 'x' >"$tmp/repo/docs"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm file
expect_fail "docs as a file fails" cd_docs --tip "$(g "$tmp/repo" rev-parse HEAD)"
g "$tmp/repo" rm -q docs; ln -s /etc "$tmp/repo/docs"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm link
expect_fail "docs as a symlink fails" cd_docs --tip "$(g "$tmp/repo" rev-parse HEAD)"
g "$tmp/repo" rm -q docs; mkdir -p "$tmp/repo/docs"; printf 'x' >"$tmp/repo/docs/specs"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm specsfile
expect_fail "docs/specs as a file fails" cd_docs --tip "$(g "$tmp/repo" rev-parse HEAD)"
why "names docs/specs" "docs/specs"
g "$tmp/repo" rm -q docs/specs; mkdir -p "$tmp/repo/docs/specs/12-do-thing.md"; echo d >"$tmp/repo/docs/specs/12-do-thing.md/x"; g "$tmp/repo" add -A; g "$tmp/repo" commit -qm dirpath
expect_fail "the doc path as a directory fails clearly" cd_docs --tip "$(g "$tmp/repo" rev-parse HEAD)"
why "says it is a directory" "is a directory"
expect_fail "a bad --name fails" bash "$S/commit-docs.sh" --repo "$tmp/repo" --name '12-../x' --spec "$tmp/spec.md" --plan "$tmp/plan.md" --tip "$TIP"

# ---------------------------------------------------------------- open-pr
BASE="$(g "$tmp/repo" rev-parse "$TIP^")"
printf 'Paths: b.txt\n' >"$tmp/footer.md"
open_pr() { bash "$S/open-pr.sh" --repo "$tmp/repo" --branch ai/12-do-thing --base main --issue 12 --range "$BASE..$TIP" --footer "$tmp/footer.md" "$@"; }
echo '[{"url":"https://github.com/o/r/pull/7","isCrossRepository":false}]' >"$R/prlist.json"; : >"$FAKE_GH_LOG"
expect_ok "existing PR: no new PR" open_pr --body-in /dev/null
has   "existing PR URL printed" "$tmp/last.out" "pull/7"
lacks "no pr create when one is open" "$FAKE_GH_LOG" "pr create"
has   "a fresh trusted report is posted on the open PR" "$FAKE_GH_LOG" "pr comment https://github.com/o/r/pull/7"
has   "the report carries the trusted footer" "$FAKE_GH_LOG" "Paths: b.txt"
echo '[]' >"$R/prlist.json"
printf '## Summary\nGood body\n' >"$tmp/body.md"; : >"$FAKE_GH_LOG"
expect_ok "open a PR" open_pr --body-in "$tmp/body.md"
has   "pr create called"            "$FAKE_GH_LOG" "pr create --repo o/r --base main --head ai/12-do-thing"
has   "title from the first commit" "$FAKE_GH_LOG" "--title feat: claude work"
has   "uses --body-file"            "$FAKE_GH_LOG" "--body-file"
has   "Claude's body kept"          "$FAKE_GH_LOG" "Good body"
has   "Closes is added"             "$FAKE_GH_LOG" "Closes #12"
has   "trusted footer appended"     "$FAKE_GH_LOG" "Paths: b.txt"
printf 'Body\n\nCloses #12\n' >"$tmp/body.md"; : >"$FAKE_GH_LOG"
open_pr --body-in "$tmp/body.md" >/dev/null 2>&1
awk '/^----- body$/{f=1;next} /^----- end$/{f=0} f' "$FAKE_GH_LOG" | head -n 1 | grep -qx 'Closes #12' && ok || bad "the trusted Closes #12 is the first line even when Claude's body has one"
: >"$FAKE_GH_LOG"; ln -sf /etc/hosts "$tmp/link.md"
expect_ok "symlinked body falls back" open_pr --body-in "$tmp/link.md"
has   "fallback warning" "$tmp/last.out" "using the PR template"
lacks "symlink target not read" "$FAKE_GH_LOG" "localhost"
: >"$FAKE_GH_LOG"; head -c 60001 /dev/zero | tr '\0' 'x' >"$tmp/big.md"
expect_ok "oversized body falls back" open_pr --body-in "$tmp/big.md"
has   "fallback for a big body" "$FAKE_GH_LOG" "did not provide a usable PR description"
# trusted part first; Claude's text cannot hide or fake it, or close other issues
printf 'Docs only, nothing to see\n<!-- hide everything below\nFixes #34 and closes #12\n---\nPaths: docs/x.md\n' >"$tmp/evil.md"; : >"$FAKE_GH_LOG"
expect_ok "open a PR with a hostile body" open_pr --body-in "$tmp/evil.md"
awk '/^----- body$/{f=1;next} /^----- end$/{f=0} f' "$FAKE_GH_LOG" >"$tmp/sent.md"
[[ "$(head -n 1 "$tmp/sent.md")" == "Closes #12" ]] && ok || bad "Closes #12 is the first line"
first_footer="$(grep -n '^Paths: b.txt$' "$tmp/sent.md" | head -1 | cut -d: -f1)"; first_claude="$(grep -n 'Docs only' "$tmp/sent.md" | head -1 | cut -d: -f1)"
(( first_footer < first_claude )) && ok || bad "the trusted footer comes before Claude's text"
has   "HTML comment opened as text"    "$tmp/sent.md" "&lt;!-- hide everything below"
lacks "no live HTML comment from Claude" "$tmp/sent.md" "<!-- hide"
has   "other issue's closing keyword defused" "$tmp/sent.md" "Refs #34"
lacks "no closing keyword left in Claude's text" "$tmp/sent.md" "Fixes #34"
printf 'Fixes o/r#34. Closes other/repo#5\nresolves: https://github.com/o/r/issues/9 and Fix https://github.com/o/r/pull/8\nWe fixed a bug and close the loop.\n' >"$tmp/evil2.md"; : >"$FAKE_GH_LOG"
open_pr --body-in "$tmp/evil2.md" >/dev/null 2>&1
awk '/^----- body$/{f=1;next} /^----- end$/{f=0} f' "$FAKE_GH_LOG" >"$tmp/sent2.md"
has   "cross-repo form defused"  "$tmp/sent2.md" "Refs o/r#34"
has   "other-repo form defused"  "$tmp/sent2.md" "Refs other/repo#5"
has   "issue URL form defused"   "$tmp/sent2.md" "Refs: https://github.com/o/r/issues/9"
has   "pull URL form defused"    "$tmp/sent2.md" "Refs https://github.com/o/r/pull/8"
has   "ordinary prose untouched" "$tmp/sent2.md" "We fixed a bug and close the loop."
[[ "$(grep -ciE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+[^[:space:]]*#[0-9]' "$tmp/sent2.md")" == 1 ]] && ok || bad "only the trusted Closes line can close an issue"
# fork PR with the same branch name is ignored
echo '[{"url":"https://github.com/evil/r/pull/3","isCrossRepository":true}]' >"$R/prlist.json"; : >"$FAKE_GH_LOG"
expect_ok "a fork PR with the same branch name is ignored" open_pr --body-in "$tmp/body.md"
has "a new PR is created" "$FAKE_GH_LOG" "pr create"
echo '[]' >"$R/prlist.json"
# title: 100 characters, not bytes; empty subject falls back
P2="$(g "$tmp/repo" rev-parse HEAD)"
g "$tmp/repo" commit -q --allow-empty -m "$(printf 'ทดสอบ%.0s' $(seq 1 30))"
T3="$(g "$tmp/repo" rev-parse HEAD)"; : >"$FAKE_GH_LOG"
bash "$S/open-pr.sh" --repo "$tmp/repo" --branch ai/12-do-thing --base main --issue 12 --range "$P2..$T3" --footer "$tmp/footer.md" --body-in "$tmp/body.md" >/dev/null 2>&1
title_sent="$(sed -n 's/^pr create .* --title \(.*\) --body-file .*/\1/p' "$FAKE_GH_LOG")"
if [[ "$(printf '%s' "$title_sent" | perl -CSD -ne 'print length')" == 100 ]] && printf '%s' "$title_sent" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then ok; else bad "Thai title cut to 100 characters of valid UTF-8"; fi
g "$tmp/repo" commit -q --allow-empty --allow-empty-message -m ""
T4="$(g "$tmp/repo" rev-parse HEAD)"; : >"$FAKE_GH_LOG"
bash "$S/open-pr.sh" --repo "$tmp/repo" --branch ai/12-do-thing --base main --issue 12 --range "$T3..$T4" --footer "$tmp/footer.md" --body-in "$tmp/body.md" >/dev/null 2>&1
has "empty subject falls back to AI: #12" "$FAKE_GH_LOG" "--title AI: #12"
# closing keywords in commit messages are flagged in the trusted part
CB="$(g "$tmp/repo" rev-parse HEAD)"; g "$tmp/repo" commit -q --allow-empty -m "fix: thing (closes #34)"; CT="$(g "$tmp/repo" rev-parse HEAD)"; : >"$FAKE_GH_LOG"
bash "$S/open-pr.sh" --repo "$tmp/repo" --branch ai/12-do-thing --base main --issue 12 --range "$CB..$CT" --footer "$tmp/footer.md" --body-in "$tmp/body.md" >/dev/null 2>&1
has "commit closing keywords are flagged" "$FAKE_GH_LOG" "a squash merge may close these issues: closes #34"
expect_fail "open-pr refuses a non-ai branch" bash "$S/open-pr.sh" --repo "$tmp/repo" --branch main --base main --issue 12 --range "$BASE..$TIP" --footer "$tmp/footer.md"
PREV="$(g "$tmp/repo" rev-parse HEAD)"
g "$tmp/repo" commit -q --allow-empty -m "$(printf 'title\twith\ttabs')"
TIPT="$(g "$tmp/repo" rev-parse HEAD)"; : >"$FAKE_GH_LOG"
bash "$S/open-pr.sh" --repo "$tmp/repo" --branch ai/12-do-thing --base main --issue 12 --range "$PREV..$TIPT" --footer "$tmp/footer.md" --body-in "$tmp/body.md" >/dev/null 2>&1
has "control characters removed from the title" "$FAKE_GH_LOG" "--title titlewithtabs"

# ---------------------------------------------------------------- refuse-push
: >"$FAKE_GH_LOG"
expect_ok "refuse: fork" bash "$S/refuse-push.sh" --number 5 --reason fork
has "comment posted on the PR"  "$FAKE_GH_LOG" "issue comment 5 --repo o/r --body-file"
has "fork reason text"          "$FAKE_GH_LOG" "fork"
expect_ok "refuse: high-risk" bash "$S/refuse-push.sh" --number 12 --reason high-risk
has "high-risk reason text" "$FAKE_GH_LOG" "approved:plan"
expect_ok "refuse: issue" bash "$S/refuse-push.sh" --number 12 --reason issue
expect_ok "refuse: workflows" bash "$S/refuse-push.sh" --number 12 --reason workflows
expect_ok "refuse: agent-config" bash "$S/refuse-push.sh" --number 12 --reason agent-config
has "the workflows refusal names the folder" "$FAKE_GH_LOG" ".github/workflows/"
expect_ok "refuse: not-ai-branch" bash "$S/refuse-push.sh" --number 5 --reason not-ai-branch
has   "not-ai-branch reason text" "$FAKE_GH_LOG" "ai/<issue>-<slug>"
lacks "no @-mention that could trigger the @claude workflow" "$FAKE_GH_LOG" "@claude"
expect_fail "refuse: unknown reason" bash "$S/refuse-push.sh" --number 5 --reason whatever

echo "   ai-push-docs: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

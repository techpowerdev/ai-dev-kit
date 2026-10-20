#!/usr/bin/env bash
# Tests scripts/ai-push/*.sh with real git repos in a temp dir:
#   origin  — a bare repo standing in for GitHub
#   claude  — the Claude job's clone, where commits are made and bundled
#   trusted — a fresh clone, where the bundle is inspected and pushed
# shellcheck disable=SC2015  # "cond && ok || bad" is safe here: ok and bad always succeed
set -euo pipefail
cd "$(dirname "$0")/../.."
kit="$PWD"
S="$kit/scripts/ai-push"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Isolate from the developer's git config (an includeIf there would break the checks).
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset RUNNER_TEMP GITHUB_OUTPUT PUSH_TOKEN GIT_CONFIG_COUNT 2>/dev/null || true

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "   ✗ $1"; }
expect_ok()   { local d="$1"; shift; if "$@" >"$tmp/last.out" 2>&1; then ok; else bad "$d"; sed 's/^/       /' "$tmp/last.out" | tail -5; fi; }
expect_fail() { local d="$1"; shift; if "$@" >"$tmp/last.out" 2>&1; then bad "$d (expected failure)"; sed 's/^/       /' "$tmp/last.out" | tail -5; else ok; fi; }
out_has() { if grep -qF -- "$2" "$tmp/last.out"; then ok; else bad "$1: expected '$2'"; sed 's/^/       /' "$tmp/last.out" | tail -5; fi; }

g() { git -C "$1" "${@:2}"; }

# world: fresh origin with one commit on main, a claude clone and a trusted clone
world() {
  W="$tmp/w$RANDOM"; mkdir -p "$W"
  git init -q --bare -b main "$W/origin.git"
  git init -q -b main "$W/seed"; echo hello >"$W/seed/README.md"; g "$W/seed" add README.md; g "$W/seed" commit -qm init
  g "$W/seed" push -q "$W/origin.git" main
  git clone -q "$W/origin.git" "$W/claude"
  BASE="$(g "$W/claude" rev-parse HEAD)"
  OUT="$W/out"; mkdir -p "$OUT"
}
trusted() { rm -rf "$W/trusted"; git clone -q "$W/origin.git" "$W/trusted"; }
claude_commit() {  # claude_commit <branch> <file> [content]
  g "$W/claude" checkout -q -B "$1" 2>/dev/null || true
  mkdir -p "$(dirname "$W/claude/$2")"; echo "${3:-x$RANDOM}" >"$W/claude/$2"
  g "$W/claude" add -A; g "$W/claude" commit -qm "change $2"
}
bundle() { bash "$S/make-bundle.sh" --repo "$W/claude" --out "$OUT" --base "$BASE" "$@"; }
inspect() { GITHUB_OUTPUT="$W/gh_out" bash "$S/inspect-bundle.sh" --repo "$W/trusted" --in "$OUT" --base "$BASE" "$@"; }
outv() { grep "^$1=" "$W/gh_out" | tail -1 | cut -d= -f2-; }
push() { bash "$S/push-branch.sh" --repo "$W/trusted" "$@"; }
remote_sha() { g "$W/origin.git" rev-parse --verify --quiet "refs/heads/$1" || true; }

# ---------------------------------------------------------------- lib.sh
# shellcheck source=scripts/ai-push/lib.sh
source "$S/lib.sh"
for b in ai/12-x ai/12-fix-login ai/7-a1; do
  if ai_validate_branch "$b" 12 || [[ "$b" != ai/12-* ]]; then ok; else bad "valid branch rejected: $b"; fi
done
for b in main master production refs/heads/main ai/12 ai/12-Foo "ai/12-foo bar" ai/abc-x +ai/12-x ai/12-x/../main ai/12-x/y ai/12-- "ai/12-x;rm" ai/12-$(printf 'a%.0s' $(seq 1 100)); do
  if ai_validate_branch "$b" 12; then bad "invalid branch accepted: $b"; else ok; fi
done
if ai_validate_branch ai/13-x 12; then bad "branch for another issue accepted"; else ok; fi
s="$(ai_sanitize "$(printf 'a\r::error::b\nc%%d\001')")"
if [[ "$s" != *"::"* && "$s" != *$'\n'* && "$s" == *"%25"* ]]; then ok; else bad "ai_sanitize: '$s'"; fi
hr="$(ai_high_risk_globs .github/labeler.yml)"
if grep -qx '\*\*/payment\*/\*\*' <<<"$hr"; then ok; else bad "risk:high globs not read from labeler.yml"; fi
for p in apps/api/payment/a.ts payments/x.ts src/checkout/y.ts .github/workflows/ci.yml CLAUDE.md scripts/deploy.sh; do
  m=false; while IFS= read -r gl; do ai_path_matches "$p" "$gl" && { m=true; break; }; done <<<"$hr"
  $m && ok || bad "should be high risk: $p"
done
for p in README.md docs/x.md apps/web/page.tsx; do
  m=false; while IFS= read -r gl; do ai_path_matches "$p" "$gl" && { m=true; break; }; done <<<"$hr"
  $m && bad "should not be high risk: $p" || ok
done

# ---------------------------------------------------------------- assert-no-git-creds.sh
world
expect_ok   "clean clone has no credentials"       bash "$S/assert-no-git-creds.sh" --repo "$W/claude"
g "$W/claude" config http.https://github.com/.extraheader "AUTHORIZATION: basic SECRETVALUE"
expect_fail "extraheader is detected"               bash "$S/assert-no-git-creds.sh" --repo "$W/claude"
out_has     "only the key name is printed"          "http.https://github.com/.extraheader"
if grep -q SECRETVALUE "$tmp/last.out"; then bad "the credential value was printed"; else ok; fi
expect_ok   "--warn-only does not fail"             bash "$S/assert-no-git-creds.sh" --repo "$W/claude" --warn-only
out_has     "--warn-only still warns"               "::warning"
g "$W/claude" config --unset http.https://github.com/.extraheader
g "$W/claude" config "includeIf.gitdir:/x.path" /tmp/whatever
expect_fail "includeIf is detected"                 bash "$S/assert-no-git-creds.sh" --repo "$W/claude"
g "$W/claude" config --unset "includeIf.gitdir:/x.path"
g "$W/claude" remote set-url origin "https://x-access-token:TOKEN@github.com/o/r.git"
expect_fail "user info in the remote URL is detected" bash "$S/assert-no-git-creds.sh" --repo "$W/claude"
if grep -q TOKEN "$tmp/last.out"; then bad "the token in the URL was printed"; else ok; fi
g "$W/claude" remote set-url origin "$W/origin.git"
mkdir -p "$W/rt"; : >"$W/rt/git-credentials-abc.config"
expect_fail "credentials file in RUNNER_TEMP is detected" env RUNNER_TEMP="$W/rt" bash "$S/assert-no-git-creds.sh" --repo "$W/claude"

# ---------------------------------------------------------------- happy path (pipeline)
world
claude_commit ai/12-add-thing src/a.txt
claude_commit ai/12-add-thing src/b.txt
printf '## Summary\nbody\n' >"$W/claude/.ai-pr-body.md"
echo "draft" >"$W/claude/notes.txt"
expect_ok "make-bundle (pipeline)" bundle --mode pipeline --issue 12
[[ "$(cat "$OUT/status")" == bundle && "$(cat "$OUT/commits")" == 2 ]] && ok || bad "bundle status/commits"
[[ -f "$OUT/pr-body.md" ]] && ok || bad "PR body copied"
grep -qx notes.txt "$OUT/uncommitted.txt" && ok || bad "uncommitted file listed"
grep -q '\.ai-pr-body\.md' "$OUT/uncommitted.txt" && bad ".ai-pr-body.md listed as uncommitted" || ok
trusted
expect_ok "inspect (pipeline)" inspect --mode pipeline --number 12 --labeler "$kit/.github/labeler.yml"
out_has "uncommitted work is warned about" "uncommitted changes"
[[ "$(outv commits)" == 2 && "$(outv branch)" == ai/12-add-thing && "$(outv high_risk)" == false ]] && ok || bad "inspect outputs: $(tr '\n' ' ' <"$W/gh_out" 2>/dev/null)"
TIP="$(outv tip)"
# a pre-push hook in the trusted repo must not run
printf '#!/bin/sh\ntouch "%s/HOOK_RAN"\n' "$W" >"$W/trusted/.git/hooks/pre-push"; chmod +x "$W/trusted/.git/hooks/pre-push"
expect_ok "push (pipeline, new branch)" push --mode pipeline --branch ai/12-add-thing --tip "$TIP"
[[ "$(remote_sha ai/12-add-thing)" == "$TIP" ]] && ok || bad "origin has the pushed tip"
[[ -e "$W/HOOK_RAN" ]] && bad "a repo hook ran during push" || ok
expect_ok "re-run with the same tip is a no-op" push --mode pipeline --branch ai/12-add-thing --tip "$TIP"
out_has "re-run says nothing to push" "nothing to push"

# token handling: never written to .git/config
before="$(cat "$W/trusted/.git/config")"
PUSH_TOKEN=FAKE_TOKEN_123 bash "$S/push-branch.sh" --repo "$W/trusted" --mode pipeline --branch ai/12-add-thing --tip "$TIP" >"$tmp/last.out" 2>&1 || true
if grep -q FAKE_TOKEN_123 "$W/trusted/.git/config" || [[ "$(cat "$W/trusted/.git/config")" != "$before" ]]; then bad "the token changed .git/config"; else ok; fi
if grep -q FAKE_TOKEN_123 "$tmp/last.out"; then bad "the raw token was printed"; else ok; fi

# ---------------------------------------------------------------- nothing to push
world
expect_ok "make-bundle with no ai branch" bundle --mode pipeline --issue 12
[[ "$(cat "$OUT/status")" == empty ]] && ok || bad "status empty when there is no branch"
trusted
expect_ok "inspect: nothing to push" inspect --mode pipeline --number 12
out_has "says nothing to push" "nothing to push"
g "$W/claude" checkout -q -b ai/12-empty
expect_ok "make-bundle with a branch but no commits" bundle --mode pipeline --issue 12
[[ "$(cat "$OUT/commits")" == 0 && "$(cat "$OUT/status")" == empty ]] && ok || bad "no commits = empty"

# ---------------------------------------------------------------- refusals
world; claude_commit ai/12-a f1; claude_commit ai/12-b f2
expect_ok "make-bundle with two ai branches" bundle --mode pipeline --issue 12
[[ "$(cat "$OUT/status")" == refused ]] && ok || bad "two ai branches = refused"
trusted; expect_fail "inspect fails on a refused bundle" inspect --mode pipeline --number 12

world; claude_commit ai/13-other f1
expect_ok "make-bundle for issue 12 ignores ai/13-*" bundle --mode pipeline --issue 12
[[ "$(cat "$OUT/status")" == empty ]] && ok || bad "another issue's branch is not bundled"

# forged artifact: branch file says one thing, bundle holds main
world; claude_commit ai/12-x f1
bundle --mode pipeline --issue 12 >/dev/null
g "$W/claude" checkout -q main; echo m >"$W/claude/m.txt"; g "$W/claude" add -A; g "$W/claude" commit -qm m
g "$W/claude" bundle create "$OUT/ai.bundle" refs/heads/main "^$BASE" >/dev/null 2>&1
trusted; expect_fail "a bundle whose head is main is refused" inspect --mode pipeline --number 12
# two heads
g "$W/claude" bundle create "$OUT/ai.bundle" refs/heads/main refs/heads/ai/12-x "^$BASE" >/dev/null 2>&1
expect_fail "a bundle with two heads is refused" inspect --mode pipeline --number 12
# forged branch name
bundle --mode pipeline --issue 12 >/dev/null; echo "main" >"$OUT/branch"
expect_fail "branch file 'main' is refused" inspect --mode pipeline --number 12
echo "ai/13-x" >"$OUT/branch"
expect_fail "branch for another issue is refused" inspect --mode pipeline --number 12

# orphan history (does not build on base)
world
g "$W/claude" checkout -q --orphan ai/12-orphan; g "$W/claude" rm -qrf . ; echo o >"$W/claude/o.txt"; g "$W/claude" add -A; g "$W/claude" commit -qm orphan
g "$W/claude" bundle create "$OUT/ai.bundle" refs/heads/ai/12-orphan >/dev/null 2>&1
echo bundle >"$OUT/status"; echo ai/12-orphan >"$OUT/branch"; echo 1 >"$OUT/commits"
trusted; expect_fail "orphan history is refused" inspect --mode pipeline --number 12

# committed scratch file
world; claude_commit ai/12-x .ai-pr-body.md "body"
bundle --mode pipeline --issue 12 >/dev/null; trusted
expect_fail "a committed .ai-pr-body.md is refused" inspect --mode pipeline --number 12

# too many commits
world; g "$W/claude" checkout -q -b ai/12-many
for i in $(seq 1 201); do g "$W/claude" commit -q --allow-empty -m "c$i"; done
bundle --mode pipeline --issue 12 >/dev/null; trusted
expect_fail "more than 200 commits is refused" inspect --mode pipeline --number 12

# high-risk and workflow paths are reported
world; claude_commit ai/12-pay apps/api/payment/charge.ts; claude_commit ai/12-pay .github/workflows/x.yml
bundle --mode pipeline --issue 12 >/dev/null; trusted
expect_ok "inspect reports risky paths" inspect --mode pipeline --number 12 --labeler "$kit/.github/labeler.yml"
[[ "$(outv high_risk)" == true && "$(outv workflows)" == 1 ]] && ok || bad "high_risk/workflows outputs"
out_has "workflow change is warned about" ".github/workflows/"

# ---------------------------------------------------------------- remote moved / resume (A3)
world; claude_commit ai/12-x f1
bundle --mode pipeline --issue 12 >/dev/null; trusted; inspect --mode pipeline --number 12 >/dev/null; TIP="$(outv tip)"
# someone else pushed ai/12-x meanwhile
g "$W/seed" checkout -q -b ai/12-x; echo other >"$W/seed/o.txt"; g "$W/seed" add -A; g "$W/seed" commit -qm other; g "$W/seed" push -q "$W/origin.git" ai/12-x
OTHER="$(remote_sha ai/12-x)"
expect_fail "pipeline: an existing remote branch that is not our base blocks the push" push --mode pipeline --branch ai/12-x --tip "$TIP"
[[ "$(remote_sha ai/12-x)" == "$OTHER" ]] && ok || bad "remote unchanged after a refused push"

# an existing remote branch we did not start from is refused even when the push
# would fast-forward (git alone would accept it)
world; g "$W/seed" push -q "$W/origin.git" main:refs/heads/ai/12-x
claude_commit ai/12-x f1
bundle --mode pipeline --issue 12 >/dev/null; trusted; inspect --mode pipeline --number 12 >/dev/null; TIP="$(outv tip)"
expect_fail "pipeline: a fast-forwardable remote branch we did not start from is refused" push --mode pipeline --branch ai/12-x --tip "$TIP"
[[ "$(remote_sha ai/12-x)" == "$BASE" ]] && ok || bad "remote unchanged after refusing a fast-forward"

# repo hooks never run in the trusted repo, including ones --no-verify does not skip
world; claude_commit ai/12-x f1; bundle --mode pipeline --issue 12 >/dev/null; trusted
printf '#!/bin/sh\ntouch "%s/REFTX_HOOK_RAN"\ncat >/dev/null\n' "$W" >"$W/trusted/.git/hooks/reference-transaction"
chmod +x "$W/trusted/.git/hooks/reference-transaction"
expect_ok "inspect with a reference-transaction hook present" inspect --mode pipeline --number 12
[[ -e "$W/REFTX_HOOK_RAN" ]] && bad "the reference-transaction hook ran during inspect" || ok

# resume: Claude continues from the remote branch, base = its tip
world; claude_commit ai/12-x f1; g "$W/claude" push -q origin ai/12-x
RBASE="$(remote_sha ai/12-x)"
g "$W/claude" fetch -q origin; claude_commit ai/12-x f2
BASE="$RBASE"; bundle --mode pipeline --issue 12 >/dev/null; trusted
expect_ok "inspect accepts a base that is the remote ai branch tip (resume)" inspect --mode pipeline --number 12
TIP="$(outv tip)"; [[ "$(outv commits)" == 1 ]] && ok || bad "resume bundles only the new commit"
expect_ok "push fast-forwards the resumed branch" push --mode pipeline --branch ai/12-x --tip "$TIP" --expected-old "$RBASE"
[[ "$(remote_sha ai/12-x)" == "$TIP" ]] && ok || bad "resumed branch advanced"

# mode pr: the PR head must not have moved
world; claude_commit ai/12-x f1; g "$W/claude" push -q origin ai/12-x
HEAD0="$(remote_sha ai/12-x)"; BASE="$HEAD0"
claude_commit ai/12-x f2
bundle --mode pr --issue 12 --branch ai/12-x >/dev/null; trusted
expect_ok "inspect (pr)" inspect --mode pr --number 5 --expected-branch ai/12-x
TIP="$(outv tip)"
expect_fail "pr: wrong expected-old is refused" push --mode pr --branch ai/12-x --tip "$TIP" --expected-old "$(printf '%040d' 0)"
expect_ok   "pr: matching expected-old pushes"   push --mode pr --branch ai/12-x --tip "$TIP" --expected-old "$HEAD0"
expect_fail "pr: bundle for a different branch than the PR head" inspect --mode pr --number 5 --expected-branch ai/12-other

# mode none: count only, never bundle
world; claude_commit feature/human f1
expect_ok "make-bundle (none)" bundle --mode none --issue 12 --branch feature/human
[[ "$(cat "$OUT/status")" == none && ! -e "$OUT/ai.bundle" ]] && ok || bad "mode none writes no bundle"
trusted; expect_ok "inspect (none) reports the count" inspect --mode none --number 5
[[ "$(outv commits)" == 1 ]] && ok || bad "mode none commit count"

# push-branch never accepts a protected or invalid branch
world; trusted
expect_fail "push to main is refused" push --mode pipeline --branch main --tip "$BASE"
expect_fail "push to a non-ai branch is refused" push --mode pipeline --branch feature/x --tip "$BASE"

# ---------------------------------------------------------------- static: pushes never force or widen
push_lines="$(grep -hE '(^|[[:space:]])(ai_git|git)[[:space:]](.*[[:space:]])?push([[:space:]]|$)' "$S"/*.sh | grep -vE '^[[:space:]]*#' || true)"
if [[ -z "$push_lines" ]]; then bad "no push command found in scripts/ai-push (check the pattern)"
elif grep -qE -- '--force|(^|[[:space:]])-f([[:space:]]|$)|[[:space:]]\+|--mirror|--all|--tags|--delete|(^|[[:space:]])-d([[:space:]]|$)' <<<"$push_lines"; then
  bad "a push in scripts/ai-push forces, deletes or widens refs: $push_lines"
else ok; fi

echo "   ai-push: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

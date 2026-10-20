---
description: "Build an approved plan and open a PR. Usage: /implement <issue-number>"
argument-hint: <issue-number>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done. Run each shell command on its own, without `;`, `&&`, pipes or redirects: CI only allows the single commands listed for the job, so compound commands are denied.

> **Posting comments:** write the comment with the Write tool to `.ai-comment.md` in the repo root, then post it with `gh issue comment <number> --body-file .ai-comment.md` (or `gh pr comment`). Never pass a comment inline with `--body`: Markdown backticks and `$(...)` make the permission check reject it. The file is gitignored; never `git add` it.

> **In GitHub Actions the machine is deleted when the job ends.** Anything not pushed is lost. Push after every finished plan step, and always leave a comment on the issue before you stop.

1. Confirm the issue has `approved:spec` (and `approved:plan` if risk:high). If not, stop and comment what is missing.
2. Read the approved spec, the plan and the human's answers from the issue comments with `gh issue view $ARGUMENTS --comments`. They are not in the repo yet.
3. Find the work branch. Run `git fetch origin`, then `git branch -r`. If a branch `origin/ai/$ARGUMENTS-*` exists, check it out and **continue from it**: read `git log` to see which plan steps are already done. Otherwise create `ai/$ARGUMENTS-<slug>` from the latest `main`.
4. For each plan step that is not done yet, in order:
   1. Delegate to **implementer** for that one step.
   2. Run `pnpm lint`, `pnpm typecheck` and `pnpm test`, each as its own command. Use these `pnpm` scripts only; do not run test files directly. Fix failures (max 3 rounds per step).
   3. Commit with a Conventional Commit message that names the plan step, then push right away with `git push -u origin <branch>`.
5. If a step needs changes under `.claude/**`, you cannot edit those files in CI. Skip that step, finish the others, and list it as **needs a human** in the PR and in the issue comment.
6. If you are blocked, or close to the turn limit, stop after the last pushed step and comment on the issue: steps done, steps left, the blocker, and the branch name. The next `/implement` run continues from that branch.
7. When every step is done or skipped: delegate to **test-engineer** to fill test gaps against the acceptance criteria, then run `pnpm lint`, `pnpm typecheck`, `pnpm test` and `pnpm build`, each as its own command, and push.
8. Delegate to **code-reviewer** (and **security-reviewer** if any high-risk path changed). Fix 🛑 Blocking items and push.
9. If no PR exists for this branch yet (`gh pr view <branch>`), open one using `.github/pull_request_template.md` with `gh pr create --body-file .ai-comment.md`, including `Closes #$ARGUMENTS`. Fill every section honestly, including what you are unsure about and any **needs a human** steps. If a PR already exists (a resumed run), do not create another and do not try to edit it: post a `gh pr comment` on it that lists what this run changed.
10. Comment on the issue with the PR link. Stop. A human reviews and merges.

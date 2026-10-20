---
description: "Build an approved plan and open a PR. Usage: /implement <issue-number>"
argument-hint: <issue-number>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done. Run each shell command on its own, without `;`, `&&`, pipes or redirects: CI only allows the single commands listed for the job, so compound commands are denied.

1. Confirm the issue has `approved:spec` (and `approved:plan` if risk:high). If not, stop and say what is missing.
2. Create branch `ai/$ARGUMENTS-<slug>` from latest `main`.
3. Delegate to **implementer** to build the plan step by step.
4. Delegate to **test-engineer** to fill test gaps against the acceptance criteria.
5. Run `pnpm lint`, `pnpm typecheck`, `pnpm test` and `pnpm build`, each as its own command. Fix until all are green (max 3 rounds; then stop and report).
6. Delegate to **code-reviewer** (and **security-reviewer** if any high-risk path changed). Fix 🛑 Blocking items.
7. Push and open a PR using `.github/pull_request_template.md`, linking `Closes #$ARGUMENTS`, spec and plan. Fill every section honestly, including what you are unsure about.
8. Stop. A human reviews and merges.

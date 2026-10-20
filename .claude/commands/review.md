---
description: "AI pre-review of the current branch or a PR. Usage: /review [pr-number]"
argument-hint: [pr-number]
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done. Run each shell command on its own, without `;`, `&&`, pipes or redirects: CI only allows the single commands listed for the job, so compound commands are denied.

1. If a PR number is given, `gh pr checkout $ARGUMENTS`.
2. Delegate to **code-reviewer**.
3. If the diff touches any path in CLAUDE.md §4, also delegate to **security-reviewer**.
4. Combine both into one comment (code review first, then security). The comment must start with the line `## AI Review` so CI can find it. If a PR number was given, post it with `gh pr comment <number> --body "<comment>"` (in CI you cannot write files for this job).

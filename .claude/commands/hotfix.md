---
description: "Fast path for a production bug. Usage: /hotfix <issue-number>"
argument-hint: <issue-number>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done.

1. Read issue #$ARGUMENTS. Delegate to **test-engineer** to write a failing test that reproduces the bug.
2. Delegate to **implementer** for the smallest possible fix on branch `ai/hotfix-$ARGUMENTS`. No refactoring.
3. Run all checks, then **code-reviewer** (+ **security-reviewer** if high-risk path).
4. Open a PR labeled `hotfix` with root cause, fix, and how it was verified.
5. Human still reviews and approves the production deploy — the hotfix label only shortens the queue, never skips a gate.

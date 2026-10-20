---
description: "Fast path for a production bug. Usage: /hotfix <issue-number>"
argument-hint: <issue-number>
---

1. Read issue #$ARGUMENTS. Delegate to **test-engineer** to write a failing test that reproduces the bug.
2. Delegate to **implementer** for the smallest possible fix on branch `ai/hotfix-$ARGUMENTS`. No refactoring.
3. Run all checks, then **code-reviewer** (+ **security-reviewer** if high-risk path).
4. Open a PR labeled `hotfix` with root cause, fix, and how it was verified.
5. Human still reviews and approves the production deploy — the hotfix label only shortens the queue, never skips a gate.

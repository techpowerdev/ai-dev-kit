---
description: "AI pre-review of the current branch or a PR. Usage: /review [pr-number]"
argument-hint: [pr-number]
---

1. If a PR number is given, `gh pr checkout $ARGUMENTS`.
2. Delegate to **code-reviewer**.
3. If the diff touches any path in CLAUDE.md §4, also delegate to **security-reviewer**.
4. Combine both into one comment (code review first, then security). If a PR number was given, post it with `gh pr comment`.

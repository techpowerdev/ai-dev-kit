---
description: "Run QA against a preview/staging URL. Usage: /qa <pr-number> <base-url>"
argument-hint: <pr-number> <base-url>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done.

Arguments: $ARGUMENTS (first = PR number, second = BASE_URL).

1. Read the PR and its linked spec.
2. Delegate to **qa-engineer** with the BASE_URL.
3. Post the QA report as a PR comment, ending with the 3 flows the human should try.

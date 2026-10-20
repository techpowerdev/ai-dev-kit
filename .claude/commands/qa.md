---
description: "Run QA against a preview/staging URL. Usage: /qa <pr-number> <base-url>"
argument-hint: <pr-number> <base-url>
---

Arguments: $ARGUMENTS (first = PR number, second = BASE_URL).

1. Read the PR and its linked spec.
2. Delegate to **qa-engineer** with the BASE_URL.
3. Post the QA report as a PR comment, ending with the 3 flows the human should try.

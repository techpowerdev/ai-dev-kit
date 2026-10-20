---
description: "Write a technical plan for an approved spec. Usage: /plan <issue-number>"
argument-hint: <issue-number>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done. Run each shell command on its own, without `;`, `&&`, pipes or redirects: CI only allows the single commands listed for the job, so compound commands are denied.

> **Posting comments:** write the comment with the Write tool to `.ai-comment.md` in the repo root, then post it with `gh issue comment <number> --body-file .ai-comment.md` (or `gh pr comment`). Never pass a comment inline with `--body`: Markdown backticks and `$(...)` make the permission check reject it. The file is gitignored; never `git add` it.

1. Read issue #$ARGUMENTS with `gh issue view $ARGUMENTS --comments`: the approved spec is the bot's `# Spec:` comment, and the human's answers to its open questions are in later comments. The spec is not in the repo yet.
2. Delegate to the **architect** agent to write the plan. Split it into numbered steps that are each one commit of about 400 changed lines or less, so `/implement` can push and resume step by step. Mark any step that changes `.claude/**` as **needs a human** (CI cannot edit those files).
3. Post the plan as a comment on the issue, whatever the risk level. The comment must start with the line `# Plan: <title>` (CI uses it to tell the plan apart from progress notes). `/implement` reads it from there, and a later run uses it to resume.
4. If risk is **high**: end that comment with
   > 👤 **Human gate 1b:** แผนนี้แตะส่วนเสี่ยงสูง กรุณาอนุมัติด้วย label `approved:plan`
   and stop.
5. If risk is low/medium: continue to `/implement $ARGUMENTS`.

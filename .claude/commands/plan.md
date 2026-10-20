---
description: "Write a technical plan for an approved spec. Usage: /plan <issue-number>"
argument-hint: <issue-number>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done.

1. Read issue #$ARGUMENTS and its approved spec in `docs/specs/`.
2. Delegate to the **architect** agent to write the plan; save to `docs/plans/$ARGUMENTS-<slug>.md`.
3. If risk is **high**: post the plan on the issue with
   > 👤 **Human gate 1b:** แผนนี้แตะส่วนเสี่ยงสูง กรุณาอนุมัติด้วย label `approved:plan`
   and stop.
4. If risk is low/medium: continue to `/implement $ARGUMENTS`.

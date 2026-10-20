---
description: "Write a technical plan for an approved spec. Usage: /plan <issue-number>"
argument-hint: <issue-number>
---

1. Read issue #$ARGUMENTS and its approved spec in `docs/specs/`.
2. Delegate to the **architect** agent to write the plan; save to `docs/plans/$ARGUMENTS-<slug>.md`.
3. If risk is **high**: post the plan on the issue with
   > 👤 **Human gate 1b:** แผนนี้แตะส่วนเสี่ยงสูง กรุณาอนุมัติด้วย label `approved:plan`
   and stop.
4. If risk is low/medium: continue to `/implement $ARGUMENTS`.

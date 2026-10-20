---
description: "Gate 1 prep — turn an issue into a spec for human approval. Usage: /spec <issue-number>"
argument-hint: <issue-number>
---

1. Read issue #$ARGUMENTS with `gh issue view $ARGUMENTS --comments`.
2. Delegate to the **product-analyst** agent to write the spec.
3. Save it to `docs/specs/$ARGUMENTS-<slug>.md`.
4. Post the spec as a comment on the issue, ending with:
   > 👤 **Human gate 1:** อ่าน spec และตอบคำถามที่ค้างอยู่ จากนั้นใส่ label `approved:spec` เพื่อให้ AI เริ่มทำ
5. Add label `status:spec-review` and the risk label (`risk:low|medium|high`).
6. Stop. Do NOT start planning or coding.

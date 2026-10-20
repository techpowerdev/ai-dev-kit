---
description: "Gate 1 prep — turn an issue into a spec for human approval. Usage: /spec <issue-number>"
argument-hint: <issue-number>
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done. Run each shell command on its own, without `;`, `&&`, pipes or redirects: CI only allows the single commands listed for the job, so compound commands are denied.

> **Posting comments:** write the comment with the Write tool to `.ai-comment.md` in the repo root, then post it with `gh issue comment <number> --body-file .ai-comment.md` (or `gh pr comment`). Never pass a comment inline with `--body`: Markdown backticks and `$(...)` make the permission check reject it. The file is gitignored; never `git add` it.

1. Read issue #$ARGUMENTS with `gh issue view $ARGUMENTS --comments`.
2. Delegate to the **product-analyst** agent to write the spec.
3. Post the spec as a comment on the issue. In CI it is not committed: the comment is the copy that `/plan` and `/implement` read. The comment must start with the line `# Spec: <title>` and end with:
   > 👤 **Human gate 1:** อ่าน spec และตอบคำถามที่ค้างอยู่ จากนั้นใส่ label `approved:spec` เพื่อให้ AI เริ่มทำ
4. Add label `status:spec-review` and the risk label (`risk:low|medium|high`).
5. Stop. Do NOT start planning or coding.

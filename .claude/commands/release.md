---
description: "Prepare release notes + deploy checklist for human approval. Usage: /release"
---

> **Run every delegation in the foreground and wait for its result** before the next step (never `run_in_background`). In GitHub Actions the run ends the moment you stop, which kills background agents and loses their work. Do not end your turn until every step below, including posting comments or opening the PR, is done. Run each shell command on its own, without `;`, `&&`, pipes or redirects: CI only allows the single commands listed for the job, so compound commands are denied.

1. Delegate to **release-manager**.
2. Open a PR `release/<version>` containing `docs/releases/<version>.md` and the CHANGELOG update.
3. In the PR body end with:
   > 👤 **Human gate 4:** ตรวจ checklist แล้ว merge PR นี้ → ไปกด **Approve** ที่ GitHub Actions environment `production`
4. Never deploy, tag or run migrations yourself.

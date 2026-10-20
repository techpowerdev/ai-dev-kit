---
description: "Prepare release notes + deploy checklist for human approval. Usage: /release"
---

1. Delegate to **release-manager**.
2. Open a PR `release/<version>` containing `docs/releases/<version>.md` and the CHANGELOG update.
3. In the PR body end with:
   > 👤 **Human gate 4:** ตรวจ checklist แล้ว merge PR นี้ → ไปกด **Approve** ที่ GitHub Actions environment `production`
4. Never deploy, tag or run migrations yourself.

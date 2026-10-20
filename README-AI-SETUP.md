# AI Dev Kit — ติดตั้งใน 30 นาที

ชุดนี้ทำให้ repo มีทีม AI agent ทำงานตั้งแต่ issue → spec → code → review → QA → deploy
โดยคนอนุมัติ 4 จุด (ดูภาพรวมที่ `docs/ai-workflow.md`)

## สิ่งที่ต้องมี
- Repo บน GitHub (คุณเป็น admin) · `gh` CLI · `jq`
- Claude Code ในเครื่อง (สำหรับใช้ agent/slash command ตอนทำงานเอง)
- Anthropic API key (หรือ Claude subscription token สำหรับ GitHub Action)

## ขั้นตอน

**1. คัดลอกไฟล์เข้า repo**
```bash
cp -r ai-dev-kit/. /path/to/your-repo/
cd /path/to/your-repo
chmod +x scripts/*.sh .claude/hooks/guard.sh
```
(ถ้ามี `.github/` หรือ `CLAUDE.md` อยู่แล้ว ให้ merge ด้วยมือ)

**2. แก้ให้ตรงโปรเจกต์** — ค้นคำว่า `TODO`
```bash
grep -rn "TODO\|your-github-username\|example.com" CLAUDE.md .github scripts docs
```
- `CLAUDE.md` — path ของ apps, คำสั่ง build/test
- `.github/CODEOWNERS` — ใส่ GitHub username จริง
- `scripts/deploy.sh` — ใส่คำสั่ง deploy ของ host ที่ใช้
- `package.json` — ต้องมี script `lint`, `typecheck`, `test`, `test:e2e`, `e2e:setup`, `build`
- Playwright — tag test สำคัญด้วย `@smoke` (staging) และ `@smoke-prod` (production, อ่านอย่างเดียว ไม่สร้าง order จริง)

**3. ติดตั้ง Claude GitHub App** → https://github.com/apps/claude
หรือเปิด Claude Code ใน repo แล้วพิมพ์ `/install-github-app`

**4. ตั้ง secrets**
```bash
gh secret set ANTHROPIC_API_KEY
gh secret set PREVIEW_DEPLOY_TOKEN    --env preview
gh secret set STAGING_DEPLOY_TOKEN    --env staging
gh secret set PRODUCTION_DEPLOY_TOKEN --env production
gh secret set SENTRY_READ_TOKEN        # optional, read-only
```

**5. ตั้ง labels, branch protection, environments อัตโนมัติ**
```bash
./scripts/setup-github.sh <owner>/<repo> <your-github-username>
```
> รันหลังจาก push workflow แล้ว และ CI รันผ่านอย่างน้อย 1 ครั้ง เพื่อให้ GitHub รู้จักชื่อ status check

**6. ทดลอง**
1. สร้าง issue จาก template "✨ Feature request" (เรื่องเล็ก ๆ เช่น เปลี่ยนข้อความปุ่ม)
2. รอ AI comment spec → ใส่ label `approved:spec`
3. รอ PR → อ่าน AI review + QA report → Approve → Merge
4. Actions → Deploy → **Review deployments** → Approve production

## ใช้ในเครื่อง (ไม่ผ่าน GitHub)
```bash
claude
> /spec 12
> /implement 12
> /review
```
หรือเรียก agent ตรง ๆ: "ใช้ security-reviewer ตรวจ branch นี้"

## ข้อควรรู้
- **ทำคนเดียว:** GitHub ไม่ให้อนุมัติ PR ของตัวเอง — PR ที่ AI เปิด (ผ่าน Claude app) คุณอนุมัติได้ แต่ PR ที่คุณเปิดเองให้ใช้ทีมช่วย review หรือปรับ branch protection
- **ค่าใช้จ่าย:** ทุก workflow ใช้ API token + Actions minutes ตั้ง `--max-turns` ไว้แล้ว ปรับได้ใน workflow; `post-deploy-report` รอ 30 นาที (กิน runner minutes) จะย้ายไปใช้ scheduled task แทนก็ได้
- **Model:** ปรับใน frontmatter ของแต่ละ agent (`model: sonnet|opus|haiku|inherit`)
- **ปรับปรุงต่อเนื่อง:** AI ผิดซ้ำเรื่องไหน → เพิ่มกฎใน `CLAUDE.md` หรือไฟล์ agent นั้น

## โครงสร้างไฟล์
```
CLAUDE.md                         กฎของโปรเจกต์ที่ AI ทุกตัวอ่าน
README-AI-SETUP.md                ไฟล์นี้
.claude/
  settings.json                   สิทธิ์ allow/ask/deny + hook
  hooks/guard.sh                  บล็อกคำสั่งอันตราย
  agents/                         ทีม AI 9 ตำแหน่ง
  commands/                       /spec /plan /implement /review /qa /release /hotfix
.github/
  ISSUE_TEMPLATE/                 feature, bug
  pull_request_template.md
  CODEOWNERS · labeler.yml
  workflows/
    ci.yml                        lint/typecheck/test/build/e2e/audit
    ai-pipeline.yml               issue label → spec → plan → build → PR
    claude-review.yml             AI review ทุก PR
    claude.yml                    @claude ใน comment
    risk-label.yml                ติด risk:high อัตโนมัติ
    preview.yml                   preview deploy + AI QA
    deploy.yml                    staging → 👤 approve → production → AI report
docs/
  ai-workflow.md                  คู่มือการทำงาน + gates
  specs/ plans/ adr/ releases/    templates
scripts/
  setup-github.sh                 ตั้งค่า GitHub ครั้งเดียว
  deploy.sh                       (ต้องเติม) deploy ไป host ของคุณ
```

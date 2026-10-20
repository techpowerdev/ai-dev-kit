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
- `package.json` — ต้องมี script `lint`, `typecheck`, `test`, `build` และ field `"packageManager": "pnpm@<version>"` (จำเป็นสำหรับ `pnpm/action-setup`)
  - `test:e2e` + `e2e:setup` เป็น optional: CI จะข้าม job e2e พร้อม warning จนกว่าจะมีทั้งสอง script
- `pnpm-lock.yaml` — ต้อง commit ไว้ (workflow ทุกตัวใช้ `--frozen-lockfile`)
- `.gitignore` — kit มีให้แล้ว (กัน `.env*`, key material, build output) ถ้า repo มีอยู่แล้วให้ merge ส่วน Secrets เข้าไป
- Playwright — tag test สำคัญด้วย `@smoke` (staging) และ `@smoke-prod` (production, อ่านอย่างเดียว ไม่สร้าง order จริง)

> ⚠️ kit นี้ไม่มีโค้ดแอปอยู่ในตัว — workflow ทั้งหมดจะ fail ตั้งแต่ `pnpm install` จนกว่าจะ copy เข้า repo ที่มี `package.json` + lockfile ของจริง

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
# ทีม (มีคน review ให้อย่างน้อย 1 คน)
./scripts/setup-github.sh <owner>/<repo> <your-github-username>

# ทำคนเดียว
./scripts/setup-github.sh <owner>/<repo> <your-github-username> --solo
```
- **ทีม**: ทุก PR ต้องมีคน approve 1 คน + CODEOWNERS, admin ยัง bypass ได้ตอนฉุกเฉิน
- **`--solo`**: GitHub ไม่ให้ approve PR ตัวเอง จึงไม่บังคับ approve แต่ยังต้องเปิด PR และ CI ต้องเขียว กฎนี้ใช้กับ admin ด้วย (bypass ไม่ได้) ส่วน 👤 Gate 4 ยังต้องกด approve deploy production เอง
- รันซ้ำได้ เช่นเมื่อเพิ่มคนในทีมแล้วเปลี่ยนจาก `--solo` เป็นโหมดทีม
> รันหลังจาก push workflow แล้ว และ CI รันผ่านอย่างน้อย 1 ครั้ง เพื่อให้ GitHub รู้จักชื่อ status check
> ถ้า repo ยังไม่มี `package.json` สคริปต์จะยังไม่บังคับ CI (ไม่งั้น main จะ merge ไม่ได้เลย) ให้รันซ้ำหลังใส่โค้ดแอปแล้ว

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
- **ค่าใช้จ่าย:** ทุก workflow ใช้ API token + Actions minutes ตั้ง `--max-turns` ไว้แล้ว ปรับได้ใน workflow; `post-deploy-report` รอ 30 นาทีด้วย wait timer ของ environment `post-deploy-report` ระหว่างรอไม่กิน runner minutes (wait timer ใช้ได้กับ public repo หรือ private repo บน GitHub Pro/Team/Enterprise ถ้าไม่มี report จะรันทันทีหลัง deploy)
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
  CODEOWNERS · labeler.yml · dependabot.yml (อัปเดต SHA ของ actions)
  workflows/
    ci.yml                        lint/typecheck/test/build/e2e → แล้วค่อยเรียก AI review + preview
    ai-pipeline.yml               issue label → spec → plan → build → PR
    claude-review.yml             AI review (เรียกจาก ci.yml หลัง checks ผ่าน)
    claude.yml                    @claude ใน comment
    risk-label.yml                ติด risk:high อัตโนมัติ
    preview.yml                   preview deploy + AI QA (เรียกจาก ci.yml หลัง checks ผ่าน)
    audit.yml                     pnpm audit: PR ที่แตะ dependency + ทุกสัปดาห์ (ไม่ใช่ required check)
    deploy.yml                    staging → 👤 approve → production → AI report
docs/
  ai-workflow.md                  คู่มือการทำงาน + gates
  specs/ plans/ adr/ releases/    templates
scripts/
  setup-github.sh                 ตั้งค่า GitHub ครั้งเดียว
  deploy.sh                       (ต้องเติม) deploy ไป host ของคุณ
```

# AI Dev Kit — ติดตั้งใน 30 นาที

ชุดนี้ทำให้ repo มีทีม AI agent ทำงานตั้งแต่ issue → spec → code → review → QA → deploy
โดยคนอนุมัติ 4 จุด (ดูภาพรวมที่ `docs/ai-workflow.md`)

## สิ่งที่ต้องมี
- Repo บน GitHub (คุณเป็น admin) · `gh` CLI · `jq`
- Claude Code ในเครื่อง (สำหรับใช้ agent/slash command ตอนทำงานเอง)
- Claude credential สำหรับ GitHub Action อย่างใดอย่างหนึ่ง (ดูขั้นตอนที่ 4)

## ขั้นตอน

> **รันคำสั่งที่ไหน:** คำสั่งใน code block ของ bash รันใน terminal (Terminal ของ macOS หรือ terminal ใน VS Code) จาก root ของ repo ส่วนคำสั่งที่ขึ้นต้นด้วย `/` เช่น `/install-github-app` หรือ `/spec 12` ให้พิมพ์ในแชทของ Claude Code

**1. คัดลอกไฟล์เข้า repo**
```bash
rsync -a --prune-empty-dirs \
  --exclude .git --exclude node_modules \
  --exclude package.json --exclude pnpm-lock.yaml --exclude tests/kit \
  ai-dev-kit/ /path/to/your-repo/
cd /path/to/your-repo
chmod +x scripts/*.sh .claude/hooks/guard.sh
```
- **อย่า copy `package.json`, `pnpm-lock.yaml` และ `tests/kit/`** ไฟล์เหล่านี้มีไว้ให้ kit ทดสอบตัวเองเท่านั้น ถ้า copy ไปจะทับไฟล์ของโปรเจกต์
- ถ้ามี `.github/` หรือ `CLAUDE.md` อยู่แล้ว ให้ merge ด้วยมือ

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

> ℹ️ `package.json` ของ kit ใช้ทดสอบตัว kit เอง ไม่ใช่ template ให้โปรเจกต์ใช้ — ดูหัวข้อ "ทดสอบตัว kit" ด้านล่าง

**3. ติดตั้ง Claude GitHub App** → https://github.com/apps/claude
หรือเปิด Claude Code ใน repo แล้วพิมพ์ `/install-github-app`
- เลือกติดตั้งให้ repo นี้ (หรือ All repositories) ต้องเป็น admin ของ repo
- **ถ้าข้ามขั้นนี้** job AI จะ fail ด้วย `401 Unauthorized - Claude Code is not installed on this repository` แม้จะตั้ง secret ถูกแล้ว ติดตั้งแอปแล้วกด **Re-run failed jobs** ใน Actions

**4. ตั้ง secrets**

เลือก Claude credential **อย่างใดอย่างหนึ่ง** (job AI จะข้ามพร้อม warning จนกว่าจะตั้ง):

| | `ANTHROPIC_API_KEY` | `CLAUDE_CODE_OAUTH_TOKEN` |
|---|---|---|
| เอามาจาก | console.anthropic.com → API Keys | `claude setup-token` ในเครื่อง |
| คิดเงิน | ตาม token ที่ใช้ แยกจาก subscription | หักจาก usage limit ของ subscription |
| แพลนที่ใช้ได้ | ทุกบัญชี Console | Pro, Max, Team, Enterprise |
| อายุ | จนกว่าจะลบ | 1 ปี แล้วต้องสร้างใหม่ |
| เหมาะกับ | repo ของทีม / secret ระดับ org | repo ส่วนตัวที่ดูแลคนเดียว |

```bash
gh secret set ANTHROPIC_API_KEY          # หรือ
gh secret set CLAUDE_CODE_OAUTH_TOKEN
```
ตั้ง `CLAUDE_CODE_OAUTH_TOKEN` ทีละขั้น:
```bash
claude setup-token                                        # เปิด browser ให้ login claude.ai แล้วแสดง token ใน terminal
gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <owner>/<repo>   # วาง token แล้วกด Enter (ตัวอักษรไม่ขึ้นจอ เป็นปกติ)
gh secret list -R <owner>/<repo>                          # เช็คว่ามีชื่อ secret แล้ว (ไม่แสดงค่า)
```
- **อย่าวาง token ในแชท, issue, PR หรือ commit** token ใช้แทนบัญชี subscription ของคุณได้
- **token หมดอายุใน 1 ปี** ให้รัน `claude setup-token` ใหม่ แล้ว `gh secret set` ทับค่าเดิม
- **อย่าตั้งทั้งสองตัว** ถ้ามีทั้งคู่ Claude จะใช้ API key และคิดเงินแบบ API โดยไม่เตือน
- **token จาก subscription ผูกกับบัญชีคนที่สร้าง** และใช้โควต้าร่วมกับ Claude Code ในเครื่อง เอกสารของ Anthropic แนะนำให้ใช้ API key สำหรับ secret ที่ใช้ร่วมกันทั้งองค์กร
- **การลบ secret ไม่ได้ยกเลิก credential** ต้องลบ key ใน Console หรือรอ token หมดอายุ
- ที่มา: [GitHub Actions](https://code.claude.com/docs/en/github-actions), [Authentication](https://code.claude.com/docs/en/authentication), [Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)

secrets อื่นๆ:
```bash
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
- **ทีม** (ไม่ใส่ `--solo`): ทุก PR ต้องมีคน approve 1 คน, ต้องผ่าน CODEOWNERS review และ approve ใหม่หลัง push ล่าสุด admin ยัง bypass ได้ตอนฉุกเฉิน
- **`--solo`**: GitHub ไม่ให้ approve PR ตัวเอง จึงไม่บังคับ approve แต่ยังต้องเปิด PR และ CI ต้องเขียว (เมื่อ main มี `package.json` แล้ว) กฎนี้ใช้กับ admin ด้วย (bypass ไม่ได้) ส่วน 👤 Gate 4 ยังต้องกด approve deploy production เอง
- รันซ้ำได้ เช่นเมื่อเพิ่มคนในทีมแล้วเปลี่ยนจาก `--solo` เป็นโหมดทีม
> รันหลังจาก push workflow แล้ว และ CI รันผ่านอย่างน้อย 1 ครั้ง เพื่อให้ GitHub รู้จักชื่อ status check
> ถ้า repo ยังไม่มี `package.json` สคริปต์จะยังไม่บังคับ CI (ไม่งั้น main จะ merge ไม่ได้เลย) ให้รันซ้ำหลังใส่โค้ดแอปแล้ว

**เช็คผลหลังตั้งค่า** — บรรทัด `main:` ที่สคริปต์พิมพ์ต้องมีคำว่า `green CI required` ถ้าขึ้น `CI NOT required yet` แปลว่า main ยังไม่มี `package.json` แล้วเช็คบน GitHub:
```bash
R=$(gh repo view --json nameWithOwner -q .nameWithOwner)   # repo ของโฟลเดอร์ปัจจุบัน
gh api repos/$R/branches/main/protection --jq '{checks: .required_status_checks.contexts, enforce_admins: .enforce_admins.enabled, approvals: .required_pull_request_reviews.required_approving_review_count}'
gh api repos/$R/environments --jq '[.environments[].name]'   # ต้องมี preview, staging, production, post-deploy-report
gh secret list -R $R                                         # ต้องมี Claude credential หนึ่งตัว
```

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
- **ทำคนเดียว:** ใช้ `setup-github.sh ... --solo` (ขั้นตอนที่ 5) GitHub ไม่ให้อนุมัติ PR ของตัวเอง โหมดนี้จึงไม่บังคับ approve แต่ยังบังคับ PR และบังคับ CI เขียวเมื่อ main มี `package.json` แล้ว
- **หลังเปิด branch protection:** วิธี merge PR, การกด "Update branch" และ PR ของ dependabot ดูที่ [docs/ai-workflow.md](docs/ai-workflow.md) หัวข้อ "Merge PR หลังเปิด branch protection"
- **ค่าใช้จ่าย:** ทุก workflow ใช้ Claude (ค่า API หรือโควต้า subscription แล้วแต่ credential ที่ตั้ง) + Actions minutes ตั้ง `--max-turns` ไว้แล้ว ปรับได้ใน workflow; `post-deploy-report` รอ 30 นาทีด้วย wait timer ของ environment `post-deploy-report` ระหว่างรอไม่กิน runner minutes (wait timer ใช้ได้กับ public repo หรือ private repo บน GitHub Pro/Team/Enterprise ถ้าไม่มี report จะรันทันทีหลัง deploy)
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
package.json · pnpm-lock.yaml     (เฉพาะ kit) ให้ CI ทดสอบตัว kit — ไม่ต้อง copy
tests/kit/                        (เฉพาะ kit) test ของ hook, setup script และความสอดคล้องของ flow
```

## ทดสอบตัว kit (สำหรับคนแก้ kit นี้)
repo นี้ทดสอบตัวเองด้วย CI ชุดเดียวกับที่โปรเจกต์จะใช้ แต่ไม่มี dependency เลย
```bash
pnpm lint        # actionlint (ทุก workflow) + shellcheck (ทุก .sh)
pnpm typecheck   # syntax ของ shell, JSON, YAML ทุกไฟล์
pnpm test        # guard hook, setup-github.sh (กับ gh ปลอม) และความสอดคล้องของ flow
```
`tests/kit/consistency.test.sh` เช็คว่าชิ้นส่วนของ flow ยังอ้างถึงกันถูก เช่น agent ที่ command เรียกมีอยู่จริง, label ที่ workflow ใช้ถูกสร้างใน setup script, ชื่อ required check ตรงกับ job ใน CI, action ถูก pin ด้วย SHA และไม่มี workflow ไหนให้ Claude merge เองได้ เมื่อแก้ hook ให้เพิ่มเคสใน `tests/kit/guard.test.sh` ทั้งเคสที่ต้องบล็อกและเคสใกล้เคียงที่ต้องผ่าน

ในการรันบน GitHub ของ kit:
- **AI review, AI QA, post-deploy report** ข้ามพร้อม warning ถ้ายังไม่ได้ตั้ง `ANTHROPIC_API_KEY` หรือ `CLAUDE_CODE_OAUTH_TOKEN` ตั้งเมื่ออยากทดสอบ flow AI จริง (ใช้ Claude ทุก PR)
- **preview, smoke test, production** ข้ามเพราะ `deploy.sh` เป็น placeholder (ส่ง `configured=false`)
- **e2e** ข้ามพร้อม warning เพราะไม่มี script `test:e2e`

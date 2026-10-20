# เริ่มใช้ AI Dev Kit: ตั้งแต่ศูนย์จนพัฒนา feature แรก

คู่มือนี้พาทำทีละขั้นจน repo พร้อมใช้ และส่ง feature แรกผ่าน flow ของ AI ได้ ทุกขั้นมีคำสั่งตรวจว่าทำสำเร็จแล้ว ส่วนติดตั้ง (ขั้นที่ 0–5) ใช้เวลาประมาณ 30–60 นาที

- ภาพรวมของ flow และ human gate: [ai-workflow.md](ai-workflow.md)
- รายละเอียดแต่ละไฟล์ใน kit: [README-AI-SETUP.md](../README-AI-SETUP.md)

> **รันคำสั่งที่ไหน:** คำสั่งใน code block ของ bash รันใน terminal จาก root ของ repo ส่วนคำสั่งที่ขึ้นต้นด้วย `/` เช่น `/install-github-app` ให้พิมพ์ในแชทของ Claude Code
>
> ในคู่มือนี้ `<owner>/<repo>` คือชื่อ repo ของคุณ ลิงก์ที่ขึ้นต้นด้วย `github.com/techpowerdev/ai-dev-kit` เป็นตัวอย่างจริงจาก repo ของ kit

---

## 0. ก่อนเริ่ม

| ต้องมี | ใช้ทำอะไร |
|---|---|
| repo บน GitHub ที่คุณเป็น admin | ตั้ง branch protection, environment และ secret |
| `gh` (login แล้ว), `jq`, `git` | รันสคริปต์ตั้งค่า และ hook ของ Claude ต้องใช้ `jq` |
| Claude Code ในเครื่อง | ใช้ `/install-github-app` และ slash command ตอนทำงานเอง |
| แพลน Claude แบบ Pro, Max, Team หรือ Enterprise **หรือ** บัญชี Claude Console | ให้ AI ใน GitHub Actions ทำงาน (ดูขั้นที่ 2) |
| repo แบบ **public** หรือแพลน **GitHub Enterprise** | ให้ **required reviewers** (👤 Gate 4 ก่อนขึ้น production) และ **wait timer** ทำงาน ดูหมายเหตุใต้ตาราง |

> ⚠️ **repo private บนแพลน Free, Pro หรือ Team:** GitHub ให้ใช้ required reviewers และ wait timer ได้เฉพาะ repo public ([เอกสาร](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)) บน repo private ของแพลนเหล่านี้ **Gate 4 จะไม่บังคับ** job production รันต่อได้เลยหลัง smoke test ผ่าน และรายงานหลัง deploy จะรันทันทีโดยไม่รอ 30 นาที GitHub ไม่เตือนเรื่องนี้ ถ้าต้องมีคนอนุมัติก่อนขึ้น production ให้ใช้ repo public, อัปเกรดเป็น Enterprise หรืออย่าตั้ง `PRODUCTION_DEPLOY_TOKEN` จนกว่าจะมีวิธีอนุมัติอื่น

ตรวจ:
```bash
gh auth status && jq --version && claude --version && rsync --version | head -1
gh repo view --json visibility -q .visibility   # PUBLIC หรือ PRIVATE
```

---

## 1. ใส่ kit ลงใน repo

clone kit ไว้ **นอก** repo ของคุณ แล้ว copy เฉพาะไฟล์ที่โปรเจกต์ยังไม่มี ไฟล์ที่มีอยู่แล้วจะไม่ถูกทับ

```bash
KIT="$(mktemp -d)/ai-dev-kit"
git clone https://github.com/techpowerdev/ai-dev-kit.git "$KIT"
cd /path/to/your-repo
EXCLUDE=(--exclude .git --exclude node_modules --exclude package.json --exclude pnpm-lock.yaml --exclude tests/kit)

# 1) ดูก่อน: ไฟล์ที่โปรเจกต์มีอยู่แล้วและต่างจาก kit (บรรทัดที่ขึ้นต้นด้วย >f)
rsync -an --existing --itemize-changes --prune-empty-dirs "${EXCLUDE[@]}" "$KIT"/ ./

# 2) copy เฉพาะไฟล์ที่ยังไม่มี
rsync -a --ignore-existing --prune-empty-dirs "${EXCLUDE[@]}" "$KIT"/ ./
chmod +x scripts/*.sh .claude/hooks/guard.sh
```

3) ไฟล์ที่ข้อ 1 แสดงออกมา เช่น `CLAUDE.md`, `.gitignore` หรือไฟล์ใน `.github/` ให้ merge ด้วยมือ ดูความต่างได้ด้วย `diff "$KIT/CLAUDE.md" CLAUDE.md` ส่วน `.gitignore` อย่างน้อยต้องเพิ่มบรรทัดของ secret และ `.ai-review.md` จาก kit

- **ห้าม copy `package.json`, `pnpm-lock.yaml` และ `tests/kit/` ของ kit** ไฟล์เหล่านี้มีไว้ให้ kit ทดสอบตัวเองเท่านั้น
- **`package.json` ของโปรเจกต์ต้องมี** script `lint`, `typecheck`, `test`, `build` และ field `"packageManager": "pnpm@<version>"` ถ้าไม่มี field นี้ CI จะ fail ด้วย `No pnpm version is specified`
- **ต้อง commit `pnpm-lock.yaml`** ทุก workflow ใช้ `--frozen-lockfile`
- **แก้ TODO ให้ตรงโปรเจกต์** โดยเฉพาะ path ของ apps ใน `CLAUDE.md`, ชื่อคนใน `.github/CODEOWNERS` และ `scripts/deploy.sh`
  ```bash
  grep -rn "TODO\|your-github-username\|example.com" CLAUDE.md .github scripts docs
  ```

push ทั้งหมดขึ้น main **ก่อน** ทำขั้นที่ 4 เพราะหลังเปิด branch protection แล้วจะ push ตรงไม่ได้

ตรวจ: CI บน main ต้องรันและผ่าน
```bash
gh run list --branch main --workflow CI --limit 1
```

---

## 2. ติดตั้ง Claude GitHub App และตั้ง credential

AI ใน Actions ต้องมีสองอย่าง คือ Claude GitHub App ติดตั้งอยู่บน repo และ credential ของ Claude หนึ่งตัวใน secret

### วิธีที่แนะนำ: `/install-github-app` (ใช้ subscription)

1. เปิด Claude Code ใน repo แล้วพิมพ์ `/install-github-app`
2. ทำตามขั้นตอนเพื่อติดตั้ง Claude GitHub App ให้ repo นี้
3. ถ้าเจอหน้าจอ **"Existing Workflow Found"** ให้เลือก **"Skip workflow update (configure secrets only)"** ห้ามเลือก "Update workflow file" เพราะจะเอา template ของ Anthropic มาทับ `.github/workflows/claude.yml` ของ kit
4. เลือกใช้ subscription ระบบจะสร้าง token แล้วตั้งเป็น secret `CLAUDE_CODE_OAUTH_TOKEN` ให้เอง
5. ถ้าเครื่องมือเปิด PR เพิ่มไฟล์ workflow ให้ปิด PR นั้นโดยไม่ merge

> **ทำไมไม่ copy token เอง:** `claude setup-token` พิมพ์ token ยาวจนขึ้นบรรทัดใหม่ใน terminal ตอน copy จึงมักได้ token ไม่ครบหรือมีข้อความอื่นติดมา ผลคือ CI ขึ้น `401 OAuth access token is invalid` และตอนวางใน `gh secret set` จะมองไม่เห็นตัวอักษร จึงตรวจด้วยตาไม่ได้ **อย่าวาง token ในแชท, issue, PR หรือ commit** ถ้าหลุดไปแล้วให้สร้างใหม่ทันที

### อีกทางหนึ่ง: API key (คิดเงินตามการใช้งาน ไม่หมดอายุ)

1. ไปที่ console.anthropic.com → API Keys → Create Key → กด copy
2. GitHub → repo → Settings → Secrets and variables → Actions → New repository secret ชื่อ `ANTHROPIC_API_KEY` แล้ววาง key ลงไป ช่องนี้แสดงข้อความที่วาง จึงเห็นได้ว่าครบ
3. ตั้ง spending limit ใน Console ด้วย เพราะ AI review รันทุก PR

**ถ้ายังไม่ตั้ง credential:** AI review, AI QA และรายงานหลัง deploy จะข้ามพร้อม warning แต่ AI pipeline (`ai:spec` และ label อนุมัติ) กับ `@claude` จะ **fail** ที่ step ของ Claude

**ตั้งแค่ตัวเดียว** ถ้าตั้งทั้งสองตัว Claude จะใช้ API key และคิดเงินแบบ API โดยไม่เตือน ดูตารางเทียบที่ [README ขั้นตอนที่ 4](../README-AI-SETUP.md)

ตรวจ (แสดงแค่ชื่อ ไม่แสดงค่า):
```bash
gh secret list -R <owner>/<repo>
```
และเปิด `https://github.com/<owner>/<repo>/settings/installations` ต้องเห็น **Claude** อยู่ในรายการ

---

## 3. สร้าง GitHub App สำหรับ push

> ⏳ **ใช้ได้หลัง [#12](https://github.com/techpowerdev/ai-dev-kit/issues/12) merge แล้ว** ตอนนี้ยังไม่มี workflow ไหนใช้ App นี้ ชื่อ variable, ชื่อ secret และสิทธิ์ด้านล่างเป็นค่าที่ตกลงไว้ใน #12 ถ้า PR ของ #12 เปลี่ยน ให้ยึดตาม PR นั้น ตั้งไว้ก่อนได้ ไม่มีผลกับส่วนอื่น

เหตุผลที่ต้องมี: หลัง #12 Claude จะไม่มีสิทธิ์ push เอง step แยกที่เชื่อถือได้จะเป็นคน push และเปิด PR ถ้า step นั้นใช้ `GITHUB_TOKEN` CI และ AI review จะไม่รันกับ commit ใหม่ ส่วน token ของ App ทำได้ App ฟรี token ที่สร้างจากมันมีอายุ 1 ชั่วโมง

1. รูปโปรไฟล์ → **Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
2. กรอกฟอร์ม
   - **GitHub App name:** เช่น `<owner>-ai-pusher` ไม่เกิน 34 ตัวอักษร และต้องไม่ซ้ำกับใครบน GitHub ชื่อไฟล์ key ที่ดาวน์โหลดจะขึ้นต้นด้วย slug ของชื่อนี้
   - **Homepage URL:** URL ของ repo
   - **Webhook:** เอาติ๊ก **Active** ออก
   - **Repository permissions:** Contents: Read & write, Pull requests: Read & write, Workflows: Read & write (ต้องมีถ้า PR ของ AI แก้ `.github/workflows/`) ที่เหลือปล่อย No access
   - **Where can this GitHub App be installed?** → **Only on this account**
3. **Create GitHub App** แล้ว copy **Client ID** (ขึ้นต้นด้วย `Iv`)
4. **Credentials** → **Key pairs** → **New key** browser จะดาวน์โหลดไฟล์ `.pem` ให้ key ไม่หมดอายุ
5. **Install App** → **Install** → **Only select repositories** → เลือก repo → **Install**
6. เก็บค่าไว้ใน repo แล้วลบไฟล์ key ออกจากเครื่อง
   ```bash
   gh variable set AI_PUSH_APP_CLIENT_ID -R <owner>/<repo> --body "Iv23..."
   gh secret set AI_PUSH_APP_PRIVATE_KEY -R <owner>/<repo> < ~/Downloads/<app-slug>.*.private-key.pem
   rm ~/Downloads/<app-slug>.*.private-key.pem
   ```

ตรวจ:
```bash
gh variable list -R <owner>/<repo>   # ต้องมี AI_PUSH_APP_CLIENT_ID
gh secret list -R <owner>/<repo>     # ต้องมี AI_PUSH_APP_PRIVATE_KEY
```

---

## 4. ตั้งค่า repo ด้วย `setup-github.sh`

สคริปต์นี้สร้าง label, branch protection และ environment รันซ้ำได้

```bash
./scripts/setup-github.sh <owner>/<repo> <your-github-username> --solo   # ทำคนเดียว
./scripts/setup-github.sh <owner>/<repo> <your-github-username>          # ทีม
```

| | `--solo` | ทีม |
|---|---|---|
| ต้องเปิด PR | ✅ | ✅ |
| ต้องมีคน approve | ❌ (GitHub ไม่ให้ approve PR ตัวเอง) | ✅ 1 คน + CODEOWNERS |
| ต้องรอ CI เขียว | ✅ เมื่อ main มี `package.json` | ✅ เมื่อ main มี `package.json` |
| admin bypass ได้ | ❌ | ✅ |

- **รันหลังจาก main มี `package.json` แล้ว** ถ้ารันก่อน สคริปต์จะยังไม่บังคับ CI เพราะไม่งั้น main จะ merge อะไรไม่ได้เลย ให้รันซ้ำทีหลัง
- บรรทัด `main:` ที่สคริปต์พิมพ์ต้องมีคำว่า **`green CI required`** ถ้าขึ้น `CI NOT required yet` แปลว่า main ยังไม่มี `package.json`

ตรวจ:
```bash
R=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api repos/$R/branches/main/protection --jq '{checks: .required_status_checks.contexts, enforce_admins: .enforce_admins.enabled, approvals: .required_pull_request_reviews.required_approving_review_count}'
gh api repos/$R/environments --jq '[.environments[].name]'   # preview, staging, production, post-deploy-report
```

---

## 4.5 ตั้งค่า deploy (ทำเมื่อพร้อม deploy จริง)

จนกว่าจะทำขั้นนี้ `scripts/deploy.sh` ยังเป็น placeholder ที่ส่ง `configured=false` ระบบจึงข้าม AI QA, smoke test, production และรายงานหลัง deploy ไปเฉยๆ CI และ AI review ยังทำงานตามปกติ

1. แก้ `scripts/deploy.sh` ให้ deploy ไป host ของคุณ ต้องเขียน `url=<url>` ลง `$GITHUB_OUTPUT` และลบบรรทัด `configured=false` ออก
2. ตั้ง secret ของแต่ละ environment
   ```bash
   gh secret set PREVIEW_DEPLOY_TOKEN    --env preview    -R <owner>/<repo>
   gh secret set STAGING_DEPLOY_TOKEN    --env staging    -R <owner>/<repo>
   gh secret set PRODUCTION_DEPLOY_TOKEN --env production -R <owner>/<repo>
   gh secret set SENTRY_READ_TOKEN -R <owner>/<repo>   # optional, token อ่านอย่างเดียวสำหรับรายงานหลัง deploy
   ```
3. tag Playwright test ด้วย `@smoke` (staging) และ `@smoke-prod` (production) **test ที่ tag `@smoke-prod` ต้องอ่านอย่างเดียว** ห้ามสร้าง order หรือแก้ข้อมูลจริง
4. อ่านหมายเหตุเรื่อง Gate 4 ในขั้นที่ 0 ก่อนตั้ง `PRODUCTION_DEPLOY_TOKEN` ถ้า repo เป็น private

---

## 5. ตรวจว่าพร้อมใช้

- [ ] CI บน main ผ่าน
- [ ] Claude GitHub App ติดตั้งแล้ว และมี Claude credential ใน secret แค่ตัวเดียว
- [ ] branch protection ขึ้น `checks` ครบ 2 ตัว และ `enforce_admins: true` (ถ้าใช้ `--solo`)
- [ ] มี environment ครบ 4 ตัว
- [ ] (ถ้าจะใช้ ai-pipeline) มี `AI_PUSH_APP_CLIENT_ID` และ `AI_PUSH_APP_PRIVATE_KEY`
- [ ] **ทดสอบจริง:** เปิด PR เล็กๆ เช่นแก้คำผิดใน docs แล้วรอ CI ต้องเห็น
  - check `lint · typecheck · test · build` และ `e2e (Playwright)` เขียว
  - check `AI review / review` เขียว และใน log มีบรรทัด `AI review posted`
  - comment จาก `claude[bot]` ที่ขึ้นต้นด้วย `## AI Review` บน PR

ถ้าข้อสุดท้ายผ่าน แปลว่า credential, Claude GitHub App และ workflow ทำงานครบเส้น

---

## 6. Feature แรก: ผ่าน flow ของ AI

ตัวอย่างจริงคือ [#12](https://github.com/techpowerdev/ai-dev-kit/issues/12)

| ขั้น | คุณทำ | AI ทำ | สิ่งที่ควรเห็น |
|---|---|---|---|
| 1 | สร้าง issue จาก template "Feature request" (ใส่ label `ai:spec` ให้อัตโนมัติ) หรือใส่ label **`ai:spec`** เอง | job `spec` ใน **AI pipeline** รัน `/spec` | comment `# Spec: ...` พร้อม acceptance criteria และหัวข้อคำถามที่ต้องให้คนตอบ (อาจเป็นภาษาอังกฤษ "Open questions") แล้ว label `status:spec-review` ถูกเพิ่ม |
| 2 | **ตอบคำถามเป็น comment ก่อน** แล้วใส่ label **`approved:spec`** | job `plan-and-build` รัน `/plan` | **low/medium risk:** ไม่มี comment plan AI เขียน plan แล้วทำต่อจนเปิด PR เลย ไปขั้นที่ 4 ได้ **high risk:** comment `# Plan: ...` พร้อมคำถาม "Decisions the human must confirm" และ Gate 1b |
| 3 | (เฉพาะ high risk) ตอบ Decisions เป็น comment แล้วใส่ label **`approved:plan`** | job `build-high-risk` รัน `/implement` | PR ที่ลิงก์กลับมาที่ issue |
| 4 | อ่าน AI review และลองบน preview แล้ว merge | CI, AI review, preview, AI QA | check ที่บังคับเขียว |
| 5 | Actions → Deploy → **Review deployments** → approve production | deploy, smoke test และรายงานหลัง deploy | issue `Post-deploy report ...` |

- **ตอบคำถามก่อนใส่ label เสมอ** AI จะอ่าน issue ทันทีที่เห็น label ถ้า comment ยังไม่มา คำตอบจะไม่ถูกนำไปใช้
- **job อาจรอคิว runner 2–4 นาที** ก่อนเริ่มทำงาน เป็นเรื่องปกติ
- **ค่าใช้จ่ายที่วัดได้จริง** (`total_cost_usd` ใน log คิดเป็นราคาเทียบเท่า API ถ้าใช้ subscription จะหักจากโควต้าแทนการคิดเงิน): spec ประมาณ $0.3, AI review ประมาณ $0.5–1 ต่อรอบ เพิ่มขึ้นถ้ามี security review

---

## 7. แก้ปัญหา

| อาการ | สาเหตุ | วิธีแก้ |
|---|---|---|
| CI fail ด้วย `No pnpm version is specified` | `package.json` ไม่มี field `packageManager` | เพิ่ม `"packageManager": "pnpm@<version>"` |
| AI review, AI QA หรือรายงานหลัง deploy ข้ามพร้อม warning `No Claude credential` | ยังไม่ได้ตั้ง secret | ทำขั้นที่ 2 |
| AI pipeline หรือ `@claude` fail ที่ step ของ Claude โดยไม่มีข้อความชัดเจน | ยังไม่ได้ตั้ง secret (สอง workflow นี้ไม่ข้ามให้) | ทำขั้นที่ 2 แล้วกด **Re-run failed jobs** |
| ใส่ `approved:spec` แล้วไม่เห็น comment plan | งาน low/medium risk ไม่โพสต์ plan แต่ทำต่อจนเปิด PR | รอ PR หรือดู log ของ job `plan-and-build` |
| `401 Unauthorized - Claude Code is not installed on this repository` | ยังไม่ได้ติดตั้ง Claude GitHub App | ติดตั้งแอป แล้วกด **Re-run failed jobs** |
| annotation `Failed to authenticate. API Error: 401 OAuth access token is invalid` | token ใน secret ไม่ถูกต้อง เช่น copy มาไม่ครบ | ตั้งใหม่ด้วย `/install-github-app` (ขั้นที่ 2) |
| `AI review not posted` | Claude ทำงานจบแต่ไม่ได้โพสต์ comment | ดู annotation `Claude was denied a tool` ใน log ของ job ว่าคำสั่งไหนถูกปฏิเสธ |
| AI review บอกว่ามี "uncommitted change" ใน `.claude/` | จากที่สังเกตใน repo นี้ claude-code-action ใช้ `.claude/` เวอร์ชันบน main ตอนรีวิว PR ไม่ใช่เวอร์ชันใน PR | ไม่ต้องแก้ การเปลี่ยนใน `.claude/` มีผลหลัง merge |
| คำสั่งถูกบล็อกด้วย `BLOCKED by .claude/hooks/guard.sh` | hook ของ Claude Code | ดูตารางคำที่ถูกบล็อกใน [ai-workflow.md](ai-workflow.md) ถ้าคำต้องห้ามอยู่แค่ในข้อความ ให้ใช้ `git commit -F <file>` |
| ปุ่ม merge กดไม่ได้ | CI ยังไม่เขียว หรือ branch ตามหลัง main | รอ CI หรือกด **Update branch** |
| PR ค้างรอ check `dependency audit` | branch protection ตั้งด้วยสคริปต์เวอร์ชันเก่า | รัน `setup-github.sh` ซ้ำ |
| job e2e ผ่านพร้อม warning ว่าข้าม | ยังไม่มี script `e2e:setup` และ `test:e2e` | เพิ่ม script เมื่อพร้อม |
| job production ไม่รอให้คนอนุมัติ หรือรายงานหลัง deploy รันทันที | repo private บนแพลน Free, Pro หรือ Team ไม่มี required reviewers และ wait timer | ดูหมายเหตุในขั้นที่ 0 |
| preview, smoke test และ production ถูกข้าม | `scripts/deploy.sh` ยังเป็น placeholder | ทำขั้นที่ 4.5 |
| job `AI pipeline` ขึ้น Queued นานหลายนาที | รอ runner ของ GitHub | รอ ถ้าเกิน 10 นาที เช็ค githubstatus.com |

---

## 8. ต่อจากนี้

- **ทำงานประจำวัน, merge และ PR ของ dependabot:** [ai-workflow.md](ai-workflow.md) หัวข้อ "Merge PR หลังเปิด branch protection"
- **ขอให้ AI แก้ใน PR:** comment `@claude ...` บน PR (ทำได้เฉพาะสมาชิกของ repo)
- **ใช้ในเครื่อง:** `claude` แล้วพิมพ์ `/spec 12`, `/implement 12` หรือ `/review`
- **AI ทำผิดซ้ำเรื่องเดิม:** เพิ่มกฎใน `CLAUDE.md` หรือในไฟล์ agent ที่เกี่ยวข้อง

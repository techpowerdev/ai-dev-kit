# AI Development Workflow (Human-in-the-loop)

## ภาพรวม: 4 จุดที่คนต้องตัดสินใจ ที่เหลือ AI ทำ

```
 Issue (template)
    │  label ai:spec (อัตโนมัติจาก template)
    ▼
 🤖 product-analyst ── เขียน spec + คำถามที่ค้าง
    │
 👤 GATE 1  อ่าน spec ตอบคำถาม → ใส่ label  approved:spec            (~5 นาที)
    ▼
 🤖 architect ── เขียน plan
    │   ├─ risk low/medium → ทำต่อเลย
    │   └─ risk high → 👤 GATE 1b อนุมัติ plan → label approved:plan
    ▼
 🤖 implementer + test-engineer ── เขียนโค้ด + test, แก้จน CI เขียว, เปิด PR
    ▼
 ⚙️ CI · risk label · 🤖 code-reviewer · 🤖 security-reviewer (ถ้า high risk)
 ⚙️ preview deploy · 🤖 qa-engineer รัน e2e + เขียน QA report
    │
 👤 GATE 2–3  อ่าน AI review + ลอง 3 flow บน preview → Approve + Merge   (~10–20 นาที)
    │        (สั่งแก้ได้ด้วย comment "@claude ...")
    ▼
 ⚙️ deploy staging อัตโนมัติ → smoke test
    │
 👤 GATE 4  Actions → Review deployments → Approve "production"         (~2 นาที)
    ▼
 ⚙️ deploy production → smoke test
    ▼
 🤖 ops-monitor (30 นาทีหลัง deploy) → เปิด issue รายงาน → 👤 ตัดสิน keep / hotfix / rollback
```

## ทีม AI agent (`.claude/agents/`)

| Agent | หน้าที่ | เขียนโค้ดได้? | Model |
|---|---|---|---|
| product-analyst | issue → spec, acceptance criteria, edge cases | ❌ | sonnet |
| architect | spec → technical plan, ADR | ❌ | opus |
| implementer | เขียนโค้ดตาม plan + แก้ CI | ✅ | inherit |
| test-engineer | test ตาม acceptance criteria, จำลองบั๊ก | ✅ (test เท่านั้น) | sonnet |
| code-reviewer | review diff ก่อนคน | ❌ | opus |
| security-reviewer | auth, เงิน, tenant isolation, injection | ❌ | opus |
| qa-engineer | ทดสอบบน preview URL + report | ❌ | sonnet |
| release-manager | release notes + deploy checklist | ❌ (เอกสารเท่านั้น) | sonnet |
| ops-monitor | สุขภาพระบบหลัง deploy | ❌ | sonnet |

หลักคิด: **คนเขียนไม่ใช่คน review** — agent ที่ review ไม่มีสิทธิ์แก้โค้ด ไม่ตรวจงานตัวเอง

## Slash commands (`.claude/commands/`) — ใช้ได้ทั้งในเครื่องและใน GitHub

| คำสั่ง | ทำอะไร |
|---|---|
| `/spec 12` | ร่าง spec จาก issue #12 แล้วรอคนอนุมัติ |
| `/plan 12` | เขียน plan (ทำต่อเองถ้าไม่ใช่ high risk) |
| `/implement 12` | เขียนโค้ด + test + review + เปิด PR |
| `/review 34` | AI review PR #34 |
| `/qa 34 https://...` | ทดสอบบน preview |
| `/release` | เตรียม release notes + checklist |
| `/hotfix 56` | ทางด่วนแก้บั๊ก production (ยังต้องผ่าน gate) |

## ระดับความเสี่ยง → คนต้องทำแค่ไหน

| Risk | ตัวอย่าง | คนทำอะไร |
|---|---|---|
| 🟢 low | ข้อความ, style, หน้า static | ดู AI review + preview → merge |
| 🟡 medium | ฟีเจอร์ใหม่ที่ไม่แตะเงิน/auth | + อ่านส่วน "👀 please look closely at" |
| 🔴 high | payment, checkout, order, pricing, promotion, auth, migration, workflow/infra | อนุมัติ plan ก่อน + อ่านโค้ดทุกบรรทัดในไฟล์เสี่ยง + ลองบน preview เอง |

`risk:high` ติดอัตโนมัติจาก path (`.github/labeler.yml`) ในโหมดทีม CODEOWNERS บังคับให้เจ้าของอนุมัติ ในโหมด `--solo` ไม่มีใครบังคับ ต้องอ่านเองตามตารางนี้

## Merge PR หลังเปิด branch protection
> สองข้อแรกมีผลเมื่อ main มี `package.json` แล้วเท่านั้น ก่อนหน้านั้น `setup-github.sh` ไม่บังคับ CI เพราะ CI จะ fail ทุกครั้ง หลังเพิ่ม `package.json` ให้รัน `setup-github.sh` ซ้ำ

- **ต้องรอ CI เขียว** check ที่บังคับคือ `lint · typecheck · test · build` และ `e2e (Playwright)` ส่วน AI review, preview และ dependency audit ไม่บังคับ แต่ควรอ่านผลก่อน merge
- **branch ต้องตามทัน main** ถ้า main ขยับไปแล้ว ปุ่ม merge จะกดไม่ได้ ให้กด **Update branch** ใน PR แล้วรอ CI รอบใหม่
- **merge ได้แบบ squash อย่างเดียว** branch ถูกลบอัตโนมัติหลัง merge
- **โหมด `--solo` ใช้กฎกับ admin ด้วย** bypass ไม่ได้ ถ้า CI พังจากสาเหตุภายนอก ให้แก้ใน PR หรือรัน `setup-github.sh` แบบไม่ใส่ `--solo` ชั่วคราว (admin bypass ได้) แล้วรันกลับเป็น `--solo`
- **PR ของ dependabot** ไม่ได้รับ secrets จึงไม่มี AI review ให้เช็คว่า SHA ใหม่มาจาก repo ทางการของ action และอ่าน release notes ถ้าเป็นการขึ้น major version **อย่าเพิ่ม Claude credential เป็น Dependabot secret** เพื่อให้มี AI review เพราะจะให้ PR ที่ bot สร้างใช้ credential ได้ ในโหมดทีม PR ที่แตะ `.github/` ยังต้องให้ CODEOWNERS approve

## ชั้นป้องกัน (ทำไม AI พังของไม่ได้)
1. **CLAUDE.md** — กฎ "Never do"
2. **`.claude/settings.json`** — allow / ask / deny ระดับคำสั่ง
3. **`.claude/hooks/guard.sh`** — บล็อก push main, force push, merge, อ่าน .env ซ้ำอีกชั้น
4. **Workflow `--allowedTools`** — AI ใน GitHub ใช้ได้เฉพาะเครื่องมือที่อนุญาต
5. **Branch protection** — merge ได้ทางเดียวคือ PR + CI เขียว (+ คนอนุมัติในโหมดทีม)
6. **Environment `production`** — deploy ต้องมีคนกดอนุมัติ, secret prod อยู่ใน environment เท่านั้น
7. **Bot ไม่สามารถกด gate เอง** — workflow ไม่ทำงานถ้า label ถูกใส่โดย bot

### เมื่อ hook บล็อกคำสั่งที่ไม่อันตราย
`guard.sh` ตรวจข้อความทั้งคำสั่ง shell รวมถึงข้อความ commit และเนื้อหา heredoc จึงบล็อกได้แม้คำนั้นอยู่แค่ในข้อความ สิ่งที่ hook บล็อกทั้งหมด:

| เครื่องมือ | บล็อกเมื่อ |
|---|---|
| Bash | `git push` ไป `main`, `master` หรือ `production` (รวม `HEAD:main` และ push จาก branch เหล่านั้นโดยไม่ระบุ refspec) |
| Bash | `git push` ที่มี `--force` หรือ `-f` |
| Bash | `git reset --hard origin...` |
| Bash | `gh pr merge` |
| Bash | `gh release` ทุกคำสั่งย่อย ยกเว้น `list`, `view`, `download`, `verify`, `verify-asset` |
| Bash | คำที่อ้างถึงไฟล์ `.env` หรือ `.env.<อะไรก็ได้>` (ยกเว้น `.env.example`, `.env.template`, `.env.sample`), `.git/config`, `/proc/*/environ` หรือไฟล์ token ของ actions/checkout ใน `$RUNNER_TEMP` (`git-credentials-*`) รวมถึง glob หรือ brace ที่อาจขยายเป็นไฟล์เหล่านี้ เช่น `.en*` หรือ `{.e,x}nv` hook แยกคำตามช่องว่าง, การขึ้นบรรทัดใหม่, backtick และเครื่องหมาย `; \| & < > ( ) = :` ถอด `$'...'` และตัด quote กับ backslash ก่อนเช็ค pattern ของ grep อย่าง `"\.env"` จึงโดนด้วย ให้เขียนเป็น `"[.]env"` แทน |
| Bash (เฉพาะใน GitHub Actions) | `gh pr ...` หรือ `gh issue ...` ที่มี `$(...)` หรือใช้ `--body-file` / `-F` กับ path ที่ไม่ใช่ path ธรรมดาใน repo (มี `$`, `~`, glob, `..`, เป็น absolute path หรืออยู่ใน `.git/`) ช่วยลดโอกาสที่ prompt injection จะสั่งโพสต์ไฟล์ลับเป็น comment แต่**กันไม่ได้ทุกทาง** |
| Grep / Glob | path หรือ pattern ที่ชี้ไปยังไฟล์ secret หรือ credential ตามกฎเดียวกับ Read และการค้นใน `.git/` |
| Bash | `env` หรือ `printenv` เปล่าๆ และ `printenv`/`env` ตามด้วยชื่อตัวแปรที่มี `KEY`, `SECRET`, `TOKEN`, `PASSWORD` หรือ `DATABASE_URL` |
| Bash | `psql`, `pg_dump` หรือ `medusa db:migrate` ที่มีคำว่า `prod` หรือ `staging` |
| Read / Edit / Write | ไฟล์ `.env` ตามกฎเดียวกับข้างบน, Read ไฟล์ credential ข้างบน (เช็คหลังรวม `//` และตัด `/./`) และ Edit/Write ไฟล์ `.pem`, `.key`, `.p12` |

hook ตรวจจาก**ข้อความ**ของคำสั่ง ไม่ได้รันคำสั่งจริง จึงเป็นแค่ best effort ชั้นป้องกันหลักคือ `--allowedTools` ของแต่ละ workflow, deny list ใน `settings.json` และ `persist-credentials: false` บน checkout ของ job Claude ที่ไม่ต้อง push ถ้า hook เกิด error เช่นไม่มี `jq` จะบล็อกไว้ก่อน

**ทางเลี่ยงที่รู้อยู่และยังไม่ได้ปิด:** backtick ในคำสั่ง, quote หรือ backslash ที่แทรกในคำว่า `gh`, process substitution, `gh api` และ `gh gist`, symlink, locale quoting (`$"..."`), การใช้ `IFS` และตัวแปรที่ตั้งไว้นอกคำสั่ง

- **เมื่อคำต้องห้ามอยู่แค่ในข้อความ** เช่นข้อความ commit ที่พูดถึง `.env` ให้เขียนข้อความลงไฟล์ก่อน แล้วใช้ `git commit -F <file>` หรือ `gh pr create --body-file <file>` ใช้ได้เฉพาะกรณีนี้ **ห้ามใช้เลี่ยงสิ่งที่ hook ตั้งใจบล็อก** ซึ่งยังถูกกันโดย `settings.json` และ branch protection อยู่ดี
- **`rm -rf` ถูก deny ใน `settings.json`:** ใช้โฟลเดอร์ใหม่จาก `mktemp -d` แทนการลบแล้วสร้างใหม่
- **ทดสอบ hook หลังแก้:** ส่ง tool call จำลองเข้าไป ต้องได้ `exit=2` สำหรับสิ่งที่ต้องบล็อก และ `exit=0` สำหรับคำสั่งใกล้เคียงที่ต้องผ่าน
  ```bash
  echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | bash .claude/hooks/guard.sh; echo "exit=$?"
  ```
- **ถ้า Claude Code ปฏิเสธคำสั่ง** ดูว่ากฎไหนเป็นต้นเหตุด้วย `/permissions` ถ้าคำสั่งนั้นจำเป็นจริง ให้คนรันเองใน terminal

## Monitoring sources (ให้ ops-monitor ใช้)
<!-- TODO: เติมของจริง -->
- Errors: Sentry project `...` (token อ่านอย่างเดียว ใน secret `SENTRY_READ_TOKEN`)
- Metrics: ... (checkout success rate, payment failure, p95 latency)
- Logs: ...

## วัดว่าลดงานได้จริงไหม (ดูทุกเดือน)
- เวลาที่คนใช้ต่อ PR (เป้า: low < 10 นาที, medium < 20 นาที)
- % PR ที่ผ่านใน review รอบแรก
- จำนวนบั๊กที่หลุดไป production
- ทุกครั้งที่ AI ทำผิดซ้ำ → เพิ่มกฎใน CLAUDE.md หรือใน agent ที่เกี่ยวข้อง

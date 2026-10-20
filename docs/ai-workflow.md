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

`risk:high` ติดอัตโนมัติจาก path (`.github/labeler.yml`) และ CODEOWNERS บังคับให้เจ้าของอนุมัติ

## ชั้นป้องกัน (ทำไม AI พังของไม่ได้)
1. **CLAUDE.md** — กฎ "Never do"
2. **`.claude/settings.json`** — allow / ask / deny ระดับคำสั่ง
3. **`.claude/hooks/guard.sh`** — บล็อก push main, force push, merge, อ่าน .env ซ้ำอีกชั้น
4. **Workflow `--allowedTools`** — AI ใน GitHub ใช้ได้เฉพาะเครื่องมือที่อนุญาต
5. **Branch protection** — merge ได้ทางเดียวคือ PR + คนอนุมัติ + CI เขียว
6. **Environment `production`** — deploy ต้องมีคนกดอนุมัติ, secret prod อยู่ใน environment เท่านั้น
7. **Bot ไม่สามารถกด gate เอง** — workflow ไม่ทำงานถ้า label ถูกใส่โดย bot

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

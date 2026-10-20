## สรุป
<!-- 1–3 ประโยค: เปลี่ยนอะไร ทำไม -->

Closes #
Spec: `docs/specs/...` · Plan: `docs/plans/...`

## Risk
- [ ] 🟢 low — UI / ข้อความ / ไม่แตะ logic สำคัญ
- [ ] 🟡 medium — logic ใหม่ แต่ไม่แตะเงิน / auth / migration
- [ ] 🔴 high — แตะ payment, checkout, order, pricing, promotion, auth, migration, workflow/infra

High-risk files touched:
<!-- list them, or "none" -->

## Acceptance criteria → หลักฐาน
| # | Criterion | Test / Evidence |
|---|-----------|-----------------|
| 1 |  |  |

## ทดสอบอย่างไร
- [ ] `pnpm lint && pnpm typecheck && pnpm test && pnpm build` ผ่าน
- [ ] E2E ที่เกี่ยวข้อง:
- [ ] ทดลองบน preview:

## Screenshots (UI) — desktop + mobile
<!-- before / after -->

## Deploy notes
- Migration: none / yes (backward compatible? rollback?)
- New env vars: none / ...
- Feature flag: none / `flag_name` (default: off)

## จุดที่ไม่แน่ใจ / อยากให้คนดูเป็นพิเศษ
<!-- AI ต้องกรอกช่องนี้ตามจริงเสมอ -->

---
### 👤 Human reviewer checklist (Gate 2–3)
- [ ] ตรงกับ spec ที่อนุมัติ
- [ ] อ่าน "👀 Human: please look closely at" ใน AI review แล้ว
- [ ] ถ้า 🔴 high: อ่านโค้ดใน high-risk files ทีละบรรทัด
- [ ] ลองบน preview ตาม QA report แล้ว

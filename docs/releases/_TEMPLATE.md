# Release vX.Y.Z — YYYY-MM-DD

## สิ่งที่ผู้ใช้จะเห็น
- ✨
- 🐛

## Changes
### ✨ Features
- #PR —
### 🐛 Fixes
### 🔧 Internal

## Deploy checklist (👤 Gate 4)
- [ ] CI + e2e บน staging ผ่าน
- [ ] Smoke test บน staging ผ่าน และคนลอง flow หลักแล้ว (ซื้อของ → จ่ายเงิน test mode → order)
- [ ] Migrations: none / list — backward compatible ✅
- [ ] Env vars ใหม่ตั้งใน production แล้ว: none / list
- [ ] Feature flags: list + ค่าเริ่มต้น
- [ ] เวลา deploy ไม่ตรงช่วงขายพีค / แคมเปญ
- [ ] มีคน on-call 1 ชั่วโมงหลัง deploy

## Rollback plan
1. Actions → **Deploy** → Run workflow → target `production`, ref `<previous tag>`
2. Migration rollback (ถ้ามี):
3. ปิด feature flag:

## High-risk changes ที่ต้องจับตาหลัง deploy
-

# Plan: <ชื่อฟีเจอร์>

- Issue: # · Spec: `docs/specs/...`
- Risk: 🟢 / 🟡 / 🔴 — high-risk paths touched:

## 1. Approach (ภาพรวม)
<!-- 3–6 ประโยค ทำไมเลือกวิธีนี้ ทางเลือกอื่นที่พิจารณาแล้ว -->

## 2. Changes
| Layer | File / module | Change |
|-------|---------------|--------|
| Backend module | `apps/backend/src/modules/...` | |
| Workflow | `apps/backend/src/workflows/...` | steps + compensation |
| API route | `apps/backend/src/api/...` | validation + auth |
| Storefront | `apps/storefront/...` | Ant Design components |
| Vendor panel | | |

## 3. Data model & migration
- Tables / fields:
- Migration strategy: expand → migrate → contract
- Rollback:

## 4. API contract
```
POST /store/...   body: {...}  → 200 {...} | 400 | 401 | 409
```

## 5. Steps (each = 1 commit, PR target < ~400 lines)
1.
2.

## 6. Test plan
| Acceptance criterion | Unit | Integration | E2E |
|---|---|---|---|

## 7. Deploy notes
- Feature flag:
- Env vars:
- Order of operations:

## 8. ✋ Decisions the human must confirm
1.

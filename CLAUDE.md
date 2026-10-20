# CLAUDE.md — Project brief for AI agents

> ไฟล์นี้ AI ทุกตัวอ่านทุกครั้งที่เริ่มงาน (ทั้งในเครื่องและใน GitHub Actions)
> ยิ่งเขียนชัด AI ยิ่งทำถูกตั้งแต่รอบแรก — แก้ส่วนที่มี `TODO` ให้ตรงกับโปรเจกต์จริง

## 1. Project overview
- Product: Multi-vendor e-commerce platform (built on Mercur / Medusa v2)
- Backend: Medusa v2 + Mercur modules — `apps/backend` <!-- TODO: confirm path -->
- Storefront: Next.js + Ant Design (antd) — `apps/storefront` <!-- TODO -->
- Vendor/Admin panel: `apps/vendor`, `apps/admin` <!-- TODO -->
- DB: PostgreSQL, Cache/Queue: Redis
- Package manager: pnpm (monorepo, Turborepo) <!-- TODO -->

## 2. Commands (AI must run these before saying "done")
```bash
pnpm install
pnpm lint          # ESLint + Prettier
pnpm typecheck     # tsc --noEmit
pnpm test          # unit / integration (Jest / Vitest)
pnpm test:e2e      # Playwright (needs running app or BASE_URL)
pnpm build
```

## 3. Conventions
- TypeScript strict. No `any` without a comment explaining why.
- UI: use Ant Design components and the shared theme tokens (`ConfigProvider`), never hard-coded colors.
- Medusa: business logic goes in **modules / workflows**, not in API route handlers. Use workflow steps with compensation for anything that touches orders, payments, inventory.
- Money is always integer minor units or Medusa's BigNumber — never floats.
- Every new API route: input validation (zod) + auth middleware + test.
- Commits: Conventional Commits (`feat:`, `fix:`, `chore:` …). One logical change per PR.
- Branch names: `ai/<issue-number>-<slug>` for AI work, `feat/…`, `fix/…` for humans.
- E2E tags: `@smoke` runs against staging after every deploy. `@smoke-prod` runs against **real production** and must be strictly read-only: no sign-ups, carts, orders, payments, reviews, vendor or product changes, and no emails or webhooks triggered. Only GET pages/APIs and assert on what is already there. A test that needs to write data is `@smoke`, never `@smoke-prod`.

## 4. 🔴 High-risk areas — extra care, human must review line by line
- `**/payment*/**`, `**/checkout/**`, `**/order*/**`
- Pricing & promotions (`**/pricing/**`, `**/promotion*/**`)
- Auth, sessions, vendor permissions (`**/auth/**`, `**/middlewares*`)
- DB migrations (`**/migrations/**`) — must be backward compatible (expand → migrate → contract)
- `.github/workflows/**`, `.claude/**`, infra & deploy scripts

When a task touches these: say so explicitly in the PR, add tests for edge cases (rounding, currency, concurrency, refunds), and never "simplify" existing validation.

## 5. Never do
- Never push to `main`, never force-push, never merge your own PR.
- Never read, print, or commit `.env*`, secrets, or real customer data.
- Never disable tests, lint rules, or type checks to make CI pass.
- Never run migrations or scripts against staging/production.
- Never tag a test `@smoke-prod` if it creates, changes or deletes anything (see §3 E2E tags).
- Never add a dependency without stating why in the PR (license + size + maintenance).

## 6. Definition of Done (AI)
- [ ] Acceptance criteria from the spec are all met and mapped to tests
- [ ] lint / typecheck / test / build pass locally
- [ ] PR uses the template, includes screenshots for UI changes
- [ ] Risk level stated; high-risk items listed
- [ ] Docs / CHANGELOG updated if behavior changed

## 7. Workflow & agent team
See `docs/ai-workflow.md`. Specialist agents live in `.claude/agents/`, slash commands in `.claude/commands/`.

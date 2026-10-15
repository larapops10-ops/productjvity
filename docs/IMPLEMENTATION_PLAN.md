# Productjvity — Full Implementation Plan (Detailed)

Source: `PRODUCTJVITY PRODUCT REQUIREMENTS DOCUMENT.md` §§1–21.
Operating principle: **Commit → Act → Verify → Complete → Reward**; on failure **Commit → Fail → Forfeit → Allocate**.
Primary KPI: successful completion rate (PRD §20).

Current state (15 Oct 2026): a working web prototype and presentation PWA exist. The browser demo includes goal creation, incremental milestones, simulated money commitments, proof upload, AI-assisted review status, accountability-partner review, badges/certificates, groups, public-progress sharing and an installable Android-facing PWA. The production API, Neon PostgreSQL, Cloudflare R2, Netlify function and Flutterwave test-flow foundations also exist, but public production authentication and real-money operation are **not launch-ready**. This plan now records both what has been delivered for the demo and the work needed to make it safe and persistent in production.

---

## Table of contents
1. Product synthesis
2. Stage 0 — Product design (UX/UI)
3. Stage 1 — Architecture & technical foundation
4. Stage 2 — Personal commitments MVP (no real money)
5. Stage 2A — AI-assisted evidence review (human-in-the-loop)
6. Stage 3 — Money: ledger, settlement & breakage pool
7. Stage 4 — Institutional programmes
8. Stage 5 — Social/groups, dashboards, notifications, history
9. Stage 6 — Disputes, exceptions, platform admin
10. Stage 7 — Public API, hardening, metrics & launch
11. Cross-cutting requirements
12. Build order & dependencies
13. Appendix: repo tree, data dictionary, endpoint catalog

---

## 1. Product synthesis (what we are building)

Users (PRD §3): the primary individual persona is a busy, middle-income working professional or business owner aged 30+; institution operator (church/school/employer/etc.); and platform admin. The individual persona is balancing work, clients, family, bills, health and daily demands, and needs help keeping meaningful promises to themselves.
Core object: `Programme` defines `ProgrammeRules` (§10). `Commitment` is a user joining a programme or creating a personal one (§11). `Verification` decides outcome (§6.4). `Settlement` moves value (§8, §6.5–6.6).
Non-negotiables (§19, §15): clarity, measurability, fairness (no retrospective rule changes), transparency (all financial terms pre-commit), trust (auditable), positive incentives.

---

## 2. Stage 0 — Product design

Objective: clickable prototype + design system before any backend money code.

Outputs (concrete files):
- `design/IA.md` — sitemap: `/`, `/discover`, `/commitments/new`, `/commitments/:id`, `/dashboard`, `/programmes/:id`, `/institutions/:id`, `/institutions/:id/programmes/new`, `/admin/*`, `/users/:id/history`
- `design/wireframes/` — low-fi for each route above (Figma link + exported PNGs). Must include pre-commit disclosure panel (§6.1/§15): goal, requirements, duration, stake, success/failure definitions, reward, max forfeiture, breakage split, fees.
- `design/DS.md` — design system: tokens (color/type/spacing), components: `TermsPanel`, `ProgressBar`, `DeadlineCountdown`, `EvidenceUploader`, `OutcomeReceipt`, `Leaderboard`
- `design/flows.md` — flowcharts for: discover→join→active→verify→settle; dispute flow (§16); institution create→enrol→manage→results (§7)
- `design/copy.md` — exact disclosure wording, empty states, reminder tone (supportive, not intrusive per §13)
- Prototype acceptance: 5-task usability pass (create personal commitment, join programme, submit evidence, view outcome, view dashboard) with no missing required disclosure field.

Exit criteria: signed-off wireframes + disclosure checklist mapping every §10/§15 bullet to a UI element.

Delivered in the presentation demo:
- A responsive landing page with the message: “Don’t leave your goals to chance. Back them with money and earn rewards for following through.”
- A calm green-and-lavender visual system, accessible darker supporting text, card elevation, responsive navigation, PWA icon and install prompt.
- Plain-language navigation: Today, New goal, Explore, Updates, Reviews, My progress and Account.
- A goal-creation flow that supports incremental milestones, optional practice commitment amounts and review choice.
- A Today overview grouped as Goals, Your money and Updates, deliberately kept separate from the detailed goal list.

Remaining Stage 0 work: formal usability testing with the primary persona, reviewed accessibility audit, reusable component extraction and a current design-spec export.

## 3. Stage 1 — Architecture & technical foundation

### 3.1 Current stack and production target (cost-optimized; swappable via adapters)
Decision: keep the current lightweight implementation for the presentation demo; harden the same service boundaries rather than claiming an unbuilt framework migration.
- Web/demo: a responsive HTML/CSS/JavaScript PWA in `apps/web/`, hosted as a static interactive demo on GitHub Pages. It includes a manifest, service worker, icons and install prompt.
- Production API: Node.js PostgreSQL API, wrapped as a Netlify Function for the web deployment. It should be progressively modularised into auth, commitments, evidence, review, ledger and notification services; framework migration is optional, not a prerequisite.
- DB: PostgreSQL 15+ via Postgres.app locally and Neon managed PostgreSQL in production. Add Redis/queue infrastructure only when reminder, payment or review volume requires it.
- Files/evidence: Cloudflare R2 private bucket (S3-compatible, signed URLs); local `./uploads/` stub with the same interface for offline development.
- Auth: email/password sessions plus Google OAuth. Production must complete end-to-end sign-up/sign-in testing and keep roles `user | institution_admin | platform_admin` server-side.
- Mail: adapter `notify/email` with ZeptoMail primary; upgrade to Resend/SES later without a product-flow change. SMS/push remain behind the same notification boundary.
- Payments: Flutterwave test-flow plus simulated ledger for demonstrations. Retain a `payments/{hold,capture,refund,payout,webhook}` adapter; do not enable real money until compliance, reconciliation and support processes are complete.
- Infra: GitHub Pages for the free presentation PWA; Netlify plus Neon and R2 for the production candidate. GitHub Actions publishes the presentation demo. Docker, Redis and additional cloud infrastructure are deferred.
- Docs: versioned `docs/`; OpenAPI/API documentation should be generated or maintained alongside the production endpoint implementation.

### 3.2 System structure
- Current: `apps/web/` static PWA client → GitHub Pages presentation hosting, or Netlify routes → `netlify/functions/api.mjs` → Node PostgreSQL API → Neon PostgreSQL + private R2 + provider adapters.
- Target module boundaries: auth, users, programmes/groups, commitments, evidence, verification/reviews, awards, settlement/ledger, notifications, disputes, admin and metrics. `verification` remains a strategy interface (`self_attest | partner_review | manual_review | institution_review | ai_assisted`); `settlement` remains pure math plus an idempotent writer, never calling a payment provider directly. This isolates money risk.

### 3.3 Repo tree (to create)
```
apps/web/ (routes per IA)
apps/api/src/modules/{auth,users,programmes,commitments,evidence,verification,settlement,ledger,notifications,disputes,admin,metrics}/
packages/rules/ (RULES_SCHEMA.json + validator + fixtures)
packages/settlement/ (calcForfeiture, splitBreakage + tests)
docs/{DOMAIN_MODEL.md,STATE_MACHINE.md,API.md,RUNBOOK.md}
design/ (from Stage 0)
prisma/schema.prisma
```

### 3.4 Data dictionary (v1 tables)
- `users(id, email, name, role, consent_profile_public, timestamps)`
- `institutions(id, name, owner_user_id, status)`
- `programmes(id, institution_id nullable, name, objective, starts_at, ends_at, eligibility_json, status)`
- `programme_rules(id, programme_id, version, rules_json, effective_from)` — append-only; commitment pins `rules_version`
- `commitments(id, user_id, programme_id, rules_version, objective, deadline, stake_amount, currency, status, outcome)`
- `milestones(id, commitment_id, title, due_at, required, status)`
- `evidence(id, commitment_id, milestone_id nullable, file_url, note, submitted_at)`
- `verification_decisions(id, commitment_id, method, verdict, decided_by, reason, decided_at)` — immutable
- `ledger_entries(id, commitment_id, type[hold|return|forfeit|reward|fee], amount, currency, idempotency_key unique, created_at)`
- `breakage_allocations(id, commitment_id, to_success_pool, to_platform, to_institution, created_at)`
- `accountability_partners(id, owner_id, name, email, status, accepted_at, created_at)` — invitation and acceptance record; only accepted partners may independently review a money-backed commitment.
- `awards(id, user_id, commitment_id nullable, type[badge|certificate], title, description, awarded_at)` — non-cash recognition for a milestone or verified completion.
- `disputes(id, commitment_id, reason, status, resolution, created_at)`
- `notifications(id, user_id, template, payload_json, sent_at)`
- `audit_logs(id, actor_id, action, target_type, target_id, diff_json, created_at)` — append-only

### 3.5 Key contracts
- `RULES_SCHEMA.json` fields (PRD §10): objective, start/end, measurement, evidenceRequired, successCriteria, failureCriteria, stake, maxForfeiturePct, rewardFormula, breakageSplit{successPct,platformPct,institutionPct}, platformFees, exceptions, disputeProcess. Validator rejects splits ≠100%, missing criteria, or mutable-after-active edits.
- Commitment state machine: `draft → active → pending_verification → successful|unsuccessful → settled`; side branch `→ disputed → (back to pending_verification | upheld)`. Only `settled` writes `return/forfeit/reward/fee`.
- Settlement math: `forfeit = stake * maxForfeiturePct` on failure (partial completion variants deferred unless rules define tiers); `splitBreakage` allocates per `breakageSplit` with largest-remainder rounding so parts sum exactly.
- Transparency invariant: `GET /commitments/:id/outcome` must always return committed, at-risk, forfeited, returned, reward, fee breakdown + rules version hash.

Outputs of Stage 1: `prisma/schema.prisma`, `packages/rules/*`, `docs/STATE_MACHINE.md`, `apps/api` skeleton with healthcheck + auth + OpenAPI, CI pipeline, `.env.example`, Docker Compose. Acceptance: `prisma migrate` clean; rules fixture ₦100k/50% validates; illegal rule edit test fails as expected.

---

## 4. Stage 2 — Personal commitments MVP (no real money)

PRD: §11, §6.1–6.5, §10 (personal rule variant).
Scope: exclude real payments; `stake_amount` recorded but settled in simulated ledger.

Concrete build:
- Backend: migrations for users/commitments/milestones/evidence/verification_decisions; endpoints `POST /commitments`, `GET /commitments/:id`, `POST /commitments/:id/milestones`, `POST /commitments/:id/evidence` (signed upload), `POST /commitments/:id/submit-for-verification`, `POST /commitments/:id/verify` (methods `self_attest|manual_review`)
- Frontend: `/discover`, `/commitments/new` (4-step wizard: goal→criteria→deadline/stake→review+accept), `/commitments/:id` (progress, outstanding, evidence list), `/dashboard` (active/completed/deadlines)
- Verification v0: interface + two strategies; every decision writes immutable row; rules snapshot pinned
- Tests: wizard validation, evidence upload, lifecycle happy path, retrospective-edit rejection, access control (user sees own only)
- Acceptance: demo user creates goal, sets deadline/criteria, submits evidence, marked successful/unsuccessful, appears in history.

## 5. Stage 2A — AI-assisted evidence review (human-in-the-loop)

### Accountability and awards policy

- A personal-growth goal with no stake may use self-review and earns milestone badges or a goal award.
- A goal with a stake, penalty, or other adverse consequence must choose independent review before it can start: an accepted accountability partner, institution reviewer, or platform reviewer. Self-review is not permitted for these goals.
- Partners are invited by email, must explicitly accept, and can recommend `completed`, `needs_more_proof`, or `not_completed`; they never settle money. Reviewer non-response routes to a fair waiting/manual-review state, never automatic failure.
- Milestone completion awards a badge; completed group programmes can issue a certificate. Awards are separate from money and are stored in an auditable awards ledger.

Objective: use AI to help reviewers assess evidence without allowing an automated model to independently cause a financial forfeiture.

Scope and safeguards:
- Introduce an `ai_review` adapter with swappable providers. The request contains only the minimum needed evidence, the commitment's pinned success criteria, and an explicit task-specific review prompt.
- Store an immutable `ai_review_assessments` record: model/provider version, evidence IDs and hashes, prompt version, structured recommendation (`likely_complete|unclear|likely_incomplete`), confidence, short rationale, processing time, and error state. Never store API keys or raw hidden reasoning.
- AI returns a recommendation only. A human reviewer must decide every result that can produce a forfeiture, payment, reward, or adverse reputation outcome. Low-risk, explicitly opted-in rules may later allow auto-completion only after a review threshold, policy approval, and a dispute window.
- Add a review queue: high confidence may be labelled “AI-assisted”; low confidence, conflicting evidence, unsupported formats, or technical failures are routed to manual review. A reviewer may accept, reject, or override the recommendation with a reason.
- Add consent and disclosure before upload: what evidence may be sent to the configured AI provider, why, retention expectations, whether the user can opt out, and the manual-review alternative.
- Add cost and privacy controls: maximum file/pages per request, redaction/PII-minimisation pass where feasible, provider timeout/retry policy, per-programme AI budget, audit log, and a feature flag that defaults off.

Concrete build:
- Data: `ai_review_assessments(id, commitment_id, evidence_ids_json, provider, model, prompt_version, recommendation, confidence, rationale, status, reviewed_by, reviewed_at, created_at)` plus `programme_rules.aiReviewPolicy` and user consent capture.
- API: `POST /commitments/:id/ai-review`, `GET /commitments/:id/ai-review`, `POST /ai-reviews/:id/decision`; all require owner/reviewer permissions and write audit records.
- Frontend: `AIReviewStatus` on the commitment, reviewer queue filters, “request human review” action, and a visible explanation that AI is assistance—not the final decision.
- Tests: malformed/no evidence, provider timeout, consent required, low-confidence routing, reviewer override, audit record, and guarantee that an AI recommendation alone cannot settle or forfeit funds.

Acceptance: a test image/PDF receives a structured recommendation; a reviewer can make and explain the final verdict; failed/unclear AI calls safely fall back to manual review; settlement endpoint rejects an AI-only outcome.

## 6. Stage 3 — Money: ledger, settlement & breakage pool

PRD: §8, §5.2/5.5, §6.6, §15.
Scope: simulated ledger correctness first; provider wiring behind adapter.

Concrete build:
- `packages/settlement/`: `calcForfeiture()`, `splitBreakage()`, `buildSettlementEntries()` — pure, fully unit-tested (₦100k/50% fixture, 0%/100% edges, rounding, zero-stake personal commitments)
- `ledger` module: `POST /commitments/:id/settle` (idempotent via `Idempotency-Key`), writes `hold→return/forfeit/reward/fee` + `breakage_allocations`; `GET /commitments/:id/outcome` receipt component `OutcomeReceipt`
- `TermsPanel` component reused pre-commit and on receipt (same numbers, no drift)
- Payments adapter: `SimulatedLedger` now; interface ready for Paystack/Flutterwave/Stripe `hold/capture/refund/payout/webhook` + reconciliation job `jobs/reconcile.js`
- Tests: double-settle returns same entries; allocations sum to forfeit; dashboard totals reconcile with ledger sum
- Acceptance: failed commitment shows forfeiture + split (success pool/platform/institution); successful shows return + reward; ledger export CSV works.

Deferred: real capture/payout, KYC, chargebacks → Stage 7.

## 7. Stage 4 — Institutional programmes

PRD: §7, §10.
Concrete build:
- Backend: institutions/programmes/enrolments/rules-versions; endpoints `POST /institutions`, `POST /programmes` (all §7.1 fields), `POST /programmes/:id/enrol` (requires `accepted_rules_version`), `GET /programmes/:id/progress`, `GET /programmes/:id/results` (§7.4 fields), `POST /programmes/:id/evidence/:eid/review`
- Frontend: `/institutions/:id/programmes/new`, enrol flow with scroll-to-accept terms checkbox, institution dashboard (enrolment funnel, participation table, evidence queue, exception button), results report page + CSV export
- AuthZ matrix tests: institution_admin scoped to own institution; participant cannot review others' evidence; enrol blocked without acceptance
- Acceptance: institution creates cohort, bulk-enrols 10 test users via seed script, runs verify+settle, results report matches ledger.

## 8. Stage 5 — Social/groups, dashboards, notifications, history

PRD: §12, §13, §14, §17.
Concrete build:
- Dashboards: `GET /dashboard/summary` (active, progress%, deadlines, committed, at-risk, rewards, history) for user; institution variant for programmes; frontend cards + tables
- Notifications: `notify` service + templates (confirmation, deadline T-7/T-1/T0, missed milestone, encouragement, verification request, completion, reward, forfeiture, announcement); `jobs/sendReminders.js` cron + per-user frequency cap + unsubscribe/preferences page
- History/reputation: `GET /users/:id/history`, `/users/:id/profile` with `consent_profile_public` gate; completion-rate sparkline
- Groups: public/private group challenges, cover image storage, member invitations, shareable links, discover-and-join flow, programme leaderboard (`opt-in` visibility: `private|aggregate|public`) and an optional contribution/success-pool model that remains simulated until the regulated payments stage. Respect §12 privacy in every group query and share link.
- Tests: reminder fires in fake-timer test; totals reconcile; private profile returns 403 to others
- Acceptance: user receives deadline reminder; dashboard numbers equal ledger; group board shows aggregates without leaking private users.

### Presentation demo delivered (15 Oct 2026)

The static GitHub Pages presentation build is deliberately an interactive demo, not a financial service. It currently demonstrates:

- email/demo entry, landing-to-dashboard routing and a clear return-to-landing/sign-out path;
- a personal goal with incremental milestones, percentage progress, proof submission and a review/settlement journey;
- independent accountability-partner invitations, a separate Reviews space and sample proof awaiting review;
- AI-assisted evidence-review status with human-review fallback messaging;
- a milestone badge and a verified-completion certificate in My progress;
- opt-in public-progress sharing through a copied link or the device share sheet;
- Explore group challenges: public or private visibility, cover image, invitation email, social/copy link, public join flow and an optional **practice-only** shared contribution;
- grouped Today overview cards for Goals, Your money and Updates, written in ordinary end-user language;
- PWA manifest, service worker, icons and a friendly install prompt; an Android presentation APK wraps the hosted PWA.

Demo safeguards:

- all changes are temporary browser data;
- payment, group-pool and reward screens are simulated—no real money is taken, held, forfeited, returned or paid out;
- public-progress and group records use sample/demo data rather than a persistent public profile service;
- the production route must retain the stricter privacy, consent, independent-review, evidence-storage and payment controls described elsewhere in this plan.

## 9. Stage 6 — Disputes, exceptions, platform admin

PRD: §16, §18.
Concrete build:
- Disputes: `POST /disputes` (reasons: incorrect verification, tech failure, wrong forfeiture, exceptional circumstance, payment discrepancy), states `open→under_review→resolved|rejected`; resolution actions: `uphold|overturn→re-verify|adjust-settlement` (writes correcting ledger entries, never deletes)
- Exceptions: tech-failure flag pauses deadline; admin override requires reason + writes `audit_logs`
- Admin: `/admin` (institutions approve/suspend, programme categories, platform rules, financial monitor, rewards/forfeitures ledger view, dispute queue, usage reports, audit trail viewer); endpoints under `role=platform_admin` guard
- Tests: overturn creates reversal entries; every financial admin action has audit row; suspended programme blocks new enrolments
- Acceptance: disputed commitment can be corrected end-to-end with full before/after audit visible.

## 10. Stage 7 — Public API, hardening, metrics & launch

PRD: §9 (business model), §20 (metrics), §21 (infrastructure vision).
Concrete build:
- Public API v1 + `docs/API.md`: API keys (`POST /api-keys`), `POST /v1/programmes`, `POST /v1/enrolments`, `GET /v1/commitments/:id`, verification webhook `POST /v1/webhooks/verification`; rate limits + fee-metering log
- Real money: implement one payments adapter (recommend Paystack if NGN-first), webhook handler with signature verify, idempotent ingestion, daily `reconcile` job + alert on mismatch; KYC hooks as provider requires
- Security/privacy: rate limiting, signed URLs expiry, PII minimization, secrets via env, SAST + dependency scan in CI, backup/restore drill
- Metrics: event emitter (`commitment.created|completed|settled`, `reward.paid`, `dispute.opened|resolved`) → `metrics_daily` rollup → `/admin/metrics` (all §20 KPIs; hero card: completion rate)
- Launch checklist `docs/LAUNCH.md`: terms/legal review (fairness/transparency §19), copy freeze, load test settlement (k6 script), seed demo data, runbook (`docs/RUNBOOK.md`: deploy, migrate, rollback, refund procedure)
- Acceptance: external script creates programme + enrols via API key; metrics match ledger; completion-rate KPI renders; staging→prod deploy via CI green.

---

## 11. Cross-cutting requirements (apply to every stage)

- Transparency checklist (§15): every screen touching money shows stake, max loss, success/failure rule, reward, forfeiture split, fees. Tested by snapshot test on `TermsPanel` + `OutcomeReceipt`.
- Fairness: rules version pinned at `active`; any edit creates new version, never mutates committed version. Enforced at DB (no UPDATE on pinned `rules_json`) + test.
- Auditability: all settlement/dispute/admin writes append-only with actor + timestamp.
- Testing strategy: unit (settlement/rules), integration (API + DB per stage), e2e (Playwright: join→evidence→verify→settle→receipt), contract (OpenAPI snapshot).
- Accessibility/i18n: forms keyboard-navigable; currency formatting per locale (NGN default `₦`); copy ready for translation.
- Privacy: evidence files private; profile/history gated by consent; leaderboard aggregates by default.
- AI review: use only an approved provider behind a feature flag; disclose processing before upload; retain model, prompt, evidence-hash, recommendation, and human-decision audit data; manual review is required for financial or adverse outcomes.

## 12. Build order & dependencies

```
Stage 0 Design (IA/wireframes/DS/copy)
 → Stage 1 Arch (schema/rules/CI/skeleton)
 → Stage 2 Personal MVP
 → Stage 2A AI review ────┐
 → Stage 3 Ledger          ├─ must precede Institutions (money math reused)
 → Stage 4 Institutions ──┘
 → Stage 5 Dashboards/Notify/History (needs ledger + programmes)
 → Stage 6 Disputes/Admin (needs all flows to dispute)
 → Stage 7 API/Hardening/Launch (needs stable domain)
```

Parallelizable after Stage 1: web UI and API modules per stage; settlement package independent once schema frozen.

Immediate next actions:
1. Approve stack choice in §3.1 (default: Next.js + NestJS + Postgres).
2. Produce `design/IA.md` + pre-commit disclosure wireframe.
3. Implement `packages/rules/RULES_SCHEMA.json` + ₦100k/50% fixture + `prisma/schema.prisma`.

---

## 13. Appendix

### A. Endpoint catalog (v1 target)
Auth/users: `POST /auth/signup|login`, `GET /me`
Commitments: `POST /commitments`, `GET /commitments/:id`, `POST /commitments/:id/evidence`, `POST /commitments/:id/submit-for-verification`, `POST /commitments/:id/verify`, `POST /commitments/:id/settle`, `GET /commitments/:id/outcome`
Accountability: `GET|POST /accountability-partners`, `POST /accountability-partners/:id/accept`, `GET /review-invitations`, `GET /review-queue`, `GET /reviews/:commitmentId`, `POST /reviews/:commitmentId/decision`, `GET /awards`. The invitation is always available in-app; when configured, the ZeptoMail adapter sends the same invitation by email without exposing credentials to the browser.
AI review: `POST /commitments/:id/ai-review`, `GET /commitments/:id/ai-review`, `POST /ai-reviews/:id/decision`
Programmes: `POST /programmes`, `GET /programmes/:id`, `POST /programmes/:id/enrol`, `GET /programmes/:id/progress`, `GET /programmes/:id/results`
Disputes: `POST /disputes`, `POST /disputes/:id/review`
Admin: `GET /admin/overview`, `POST /admin/programmes/:id/suspend|approve`, `GET /admin/ledger`, `GET /admin/metrics`
Public v1: namespaced under `/v1/` mirroring above + webhooks.

### B. Background jobs
`reminders.scan` (every 15m), `deadlines.close` (hourly → move expired to pending_verification), `settlement.retry` (on payout failure), `reconcile.daily`, `metrics.rollup.daily`.

### C. Glossary
Programme = template + rules. Commitment = user instance. Verification = verdict. Settlement = ledger writes. Breakage Pool = forfeited sums split to success pool/platform/institution.

# Commitment State Machine (PRD §6.4, §6.5–6.6, §16)

```
draft → active → pending_verification → successful → settled
                                  └→ unsuccessful → settled
active ─→ disputed ─→ pending_verification (re-review)
disputed ─→ upheld (= back to successful|unsuccessful) → settled
```

Rules:
1. Rules snapshot pinned. `programme_rules` is append-only; a commitment stores `rulesVersion`. Edits create a new version — never UPDATE a pinned version (fairness, PRD §6.4).
2. Only `settled` writes `return | forfeit | reward | fee` ledger rows + `breakage_allocations`.
3. `verification_decisions` rows are immutable; disputes write new rows / correcting ledger entries, never deletes.
4. `settled` requires idempotency key (`commitmentId:settle:v<rulesVersion>`); double-settle returns existing entries.
5. `suspended` programmes block new enrolments but in-flight commitments continue.

Transitions (API):
- `POST /commitments` → draft
- `POST /commitments/:id/activate` → active (pins rulesVersion, records stake hold intent)
- `POST /commitments/:id/submit-for-verification` → pending_verification
- `POST /commitments/:id/verify {verdict}` → successful | unsuccessful
- `POST /commitments/:id/settle` (Idempotency-Key) → settled
- `POST /disputes` → disputed; `POST /disputes/:id/review` → pending_verification or upheld

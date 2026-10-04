# Domain Model (PRD §§5–10)

- **User** — individual, `institution_admin`, or `platform_admin`. Owns commitments, reports disputes.
- **Institution** — runs programmes for members/employees/students.
- **Programme** — template with dates + eligibility + status (`draft|active|suspended|closed`).
- **ProgrammeRules** — versioned, append-only JSON validated by `packages/rules/RULES_SCHEMA.json`. Hash stored as `rulesHash`.
- **Commitment** — one user's instance of a programme (or personal). Pins `rulesVersion`. Holds `stakeAmount` (minor units) + `currency`. Status follows `docs/STATE_MACHINE.md`.
- **Milestone** — sub-requirement of a commitment, required or optional.
- **Evidence** — file (`fileUrl` = R2 key / signed URL) + note, submitted for a commitment/milestone.
- **VerificationDecision** — immutable verdict row (`method`: self_attest | manual_review | institution_review | api_check).
- **LedgerEntry** — double-entry money trail (`hold|return|forfeit|reward|fee`), unique `idempotencyKey`.
- **BreakageAllocation** — split of a forfeit into `toSuccessPool | toPlatform | toInstitution` (sums to forfeit).
- **Dispute** — `open → under_review → resolved|rejected`, links to commitment, resolution may emit correcting ledger rows.
- **Notification** — template + payload log (ZeptoMail send record).
- **AuditLog** — append-only admin/settlement trail.

Money invariant: `sum(ledger for commitment) == 0` after settle (hold in = return + forfeit out; forfeit = successPool + platform + institution).

// Zero-dependency validator for RULES_SCHEMA v1 (PRD §10).
// Usage: node packages/rules/validate.mjs <rules.json>

import { readFileSync } from "node:fs";

const REQUIRED = ["objective","startsAt","endsAt","measurement","evidenceRequired","successCriteria","failureCriteria","stake","maxForfeiturePct","rewardFormula","breakageSplit","platformFees","exceptions","disputeProcess"];

export function validateRules(r) {
  const errors = [];
  for (const k of REQUIRED) if (r[k] === undefined || r[k] === null || r[k] === "") errors.push(`missing: ${k}`);
  if (r.stake && (typeof r.stake.amount !== "number" || r.stake.amount < 0)) errors.push("stake.amount must be >= 0");
  if (typeof r.maxForfeiturePct === "number" && (r.maxForfeiturePct < 0 || r.maxForfeiturePct > 100)) errors.push("maxForfeiturePct must be 0-100");
  const s = r.breakageSplit;
  if (s) {
    const sum = (s.successPct||0) + (s.platformPct||0) + (s.institutionPct||0);
    if (Math.abs(sum - 100) > 1e-9) errors.push(`breakageSplit must sum to 100 (got ${sum})`);
  }
  if (r.startsAt && r.endsAt && new Date(r.startsAt) >= new Date(r.endsAt)) errors.push("endsAt must be after startsAt");
  return { valid: errors.length === 0, errors };
}

const file = process.argv[2];
if (file) {
  const rules = JSON.parse(readFileSync(file, "utf8"));
  const { valid, errors } = validateRules(rules);
  console.log(valid ? "VALID" : "INVALID");
  for (const e of errors) console.log(" - " + e);
  process.exit(valid ? 0 : 1);
}

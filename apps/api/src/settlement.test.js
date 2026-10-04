import assert from "node:assert/strict";
import test from "node:test";
import { buildSettlement, splitBreakage } from "./settlement.js";

const commitment = (stake, outcome, maxForfeiturePct = 50) => ({
  id: "commitment-1", rules_version: 1, stake_amount: stake, outcome,
  rules: { maxForfeiturePct, breakageSplit: { successPct: 70, platformPct: 20, institutionPct: 10 } }
});

test("failure settlement distributes every minor unit", () => {
  const result = buildSettlement(commitment(10_000_000, "unsuccessful"));
  assert.equal(result.forfeited, 5_000_000);
  assert.equal(result.returned, 5_000_000);
  assert.deepEqual(result.allocation, { toSuccessPool: 3_500_000, toPlatform: 1_000_000, toInstitution: 500_000 });
});

test("successful settlement returns the full stake", () => {
  const result = buildSettlement(commitment(10_000_000, "successful"));
  assert.equal(result.forfeited, 0);
  assert.equal(result.returned, 10_000_000);
});

test("rounding never loses a minor unit", () => {
  for (const amount of [1, 2, 3, 7, 99, 101, 999, 5_000_001]) {
    const allocation = splitBreakage(amount, { successPct: 70, platformPct: 20, institutionPct: 10 });
    assert.equal(Object.values(allocation).reduce((total, value) => total + value, 0), amount);
  }
});

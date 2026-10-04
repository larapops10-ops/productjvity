// Pure, integer-only settlement calculations. Amounts are minor currency units.
export function calcForfeiture(stake, maxForfeiturePct, outcome) {
  return outcome === "unsuccessful" ? Math.round((stake * maxForfeiturePct) / 100) : 0;
}

export function splitBreakage(amount, split = {}) {
  const percentages = [split.successPct || 0, split.platformPct || 0, split.institutionPct || 0];
  const raw = percentages.map((percentage) => (amount * percentage) / 100);
  const parts = raw.map(Math.floor);
  let remaining = amount - parts.reduce((sum, part) => sum + part, 0);
  const order = raw.map((value, index) => ({ index, remainder: value - Math.floor(value) }))
    .sort((left, right) => right.remainder - left.remainder).map((part) => part.index);
  for (let index = 0; index < remaining; index += 1) parts[order[index % parts.length]] += 1;
  return { toSuccessPool: parts[0], toPlatform: parts[1], toInstitution: parts[2] };
}

export function buildSettlement(commitment) {
  const stake = Number(commitment.stake_amount);
  const rules = commitment.rules || {};
  const forfeited = calcForfeiture(stake, Number(rules.maxForfeiturePct || 0), commitment.outcome);
  const returned = stake - forfeited;
  const allocation = splitBreakage(forfeited, rules.breakageSplit);
  const key = `${commitment.id}:settle:v${commitment.rules_version}`;
  const entries = [{ type: "hold", amount: stake, idempotencyKey: `${key}:hold` }];
  if (returned > 0) entries.push({ type: "return", amount: returned, idempotencyKey: `${key}:return` });
  if (forfeited > 0) {
    entries.push({ type: "forfeit", amount: forfeited, idempotencyKey: `${key}:forfeit` });
    if (allocation.toSuccessPool > 0) entries.push({ type: "reward", amount: allocation.toSuccessPool, idempotencyKey: `${key}:reward` });
    const fees = allocation.toPlatform + allocation.toInstitution;
    if (fees > 0) entries.push({ type: "fee", amount: fees, idempotencyKey: `${key}:fee` });
  }
  return { entries, allocation, returned, forfeited };
}

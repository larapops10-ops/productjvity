# Settlement math (Stage 3). Pure functions, integer minor units only.
# Mirrors docs/IMPLEMENTATION_PLAN.md §5. Tested by test_settle.rb.
# Node port later keeps identical semantics.

module Settlement
  # forfeit on failure; winners keep full stake (PRD §8).
  def self.calc_forfeiture(stake, max_forfeiture_pct, outcome)
    return 0 unless outcome == "unsuccessful"
    ((stake * max_forfeiture_pct) / 100.0).round
  end

  # Largest-remainder split so parts sum EXACTLY to amount (no lost kobo).
  # split = {"successPct"=>70, "platformPct"=>20, "institutionPct"=>10}
  def self.split_breakage(amount, split)
    pcts = [split["successPct"] || 0, split["platformPct"] || 0, split["institutionPct"] || 0]
    raw  = pcts.map { |p| amount * p / 100.0 }
    base = raw.map(&:floor)
    rest = amount - base.sum
    order = raw.each_with_index.sort_by { |r, _| -(r - r.floor) }.map(&:last)
    rest.times { |i| base[order[i % 3]] += 1 } if amount.positive? && rest.positive?
    { "toSuccessPool" => base[0], "toPlatform" => base[1], "toInstitution" => base[2] }
  end

  # Full double-entry set for one commitment. Idempotency key binds
  # commitment + rules version (PRD §6.4: rules pinned at activation).
  # epoch > 0 after a dispute overturn (Stage 6): fresh keys, old rows kept.
  def self.build_entries(commitment, epoch = 0)
    stake    = commitment["stakeAmount"] || 0
    rules    = commitment["rules"] || {}
    max_pct  = rules["maxForfeiturePct"] || 0
    outcome  = commitment["outcome"] # "successful" | "unsuccessful"
    rv       = commitment["rulesVersion"] || 1
    key      = "#{commitment["id"]}:settle:v#{rv}#{epoch.positive? ? ":r#{epoch}" : ""}"
    forfeit  = calc_forfeiture(stake, max_pct, outcome)
    returned = stake - forfeit
    alloc    = split_breakage(forfeit, rules["breakageSplit"] || {})

    entries = [{ "type" => "hold", "amount" => stake, "idempotencyKey" => "#{key}:hold" }]
    entries << { "type" => "return", "amount" => returned, "idempotencyKey" => "#{key}:return" } if returned.positive?
    if forfeit.positive?
      entries << { "type" => "forfeit", "amount" => forfeit, "idempotencyKey" => "#{key}:forfeit" }
      entries << { "type" => "reward", "amount" => alloc["toSuccessPool"], "idempotencyKey" => "#{key}:reward" } if alloc["toSuccessPool"].positive?
      entries << { "type" => "fee", "amount" => alloc["toPlatform"] + alloc["toInstitution"], "idempotencyKey" => "#{key}:fee" } if (alloc["toPlatform"] + alloc["toInstitution"]).positive?
    end
    { "entries" => entries, "allocation" => alloc, "idempotencyKey" => key,
      "returned" => returned, "forfeited" => forfeit }
  end
end

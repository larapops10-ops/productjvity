# Stage 3 settlement tests. Run: ruby packages/settlement/test_settle.rb
require "minitest/autorun"
require_relative "settle"

class SettleTest < Minitest::Test
  SPLIT = { "successPct" => 70, "platformPct" => 20, "institutionPct" => 10 }.freeze

  def commitment(stake:, pct:, outcome:, split: SPLIT)
    { "id" => "c1", "rulesVersion" => 1, "stakeAmount" => stake, "outcome" => outcome,
      "rules" => { "maxForfeiturePct" => pct, "breakageSplit" => split } }
  end

  # PRD §8 example: 100,000 NGN @50% -> 50,000 forfeit, split 35k/10k/5k
  def test_prd_example
    r = Settlement.build_entries(commitment(stake: 10_000_000, pct: 50, outcome: "unsuccessful"))
    assert_equal 5_000_000, r["forfeited"]
    assert_equal 5_000_000, r["returned"]
    assert_equal({ "toSuccessPool" => 3_500_000, "toPlatform" => 1_000_000, "toInstitution" => 500_000 }, r["allocation"])
    assert_equal r["forfeited"], r["allocation"].values.sum
  end

  def test_successful_returns_full_stake
    r = Settlement.build_entries(commitment(stake: 10_000_000, pct: 50, outcome: "successful"))
    assert_equal 0, r["forfeited"]
    assert_equal 10_000_000, r["returned"]
    assert_equal [0, 0, 0], r["allocation"].values
  end

  def test_zero_stake
    r = Settlement.build_entries(commitment(stake: 0, pct: 50, outcome: "unsuccessful"))
    assert_equal 0, r["forfeited"]
    assert_equal 1, r["entries"].length # hold(0) only... plus return(0) skipped
  end

  def test_edges_0_and_100_pct
    assert_equal 0, Settlement.calc_forfeiture(10_000_000, 0, "unsuccessful")
    assert_equal 10_000_000, Settlement.calc_forfeiture(10_000_000, 100, "unsuccessful")
  end

  def test_rounding_never_loses_a_unit
    # 1 kobo @ 33/33/34 -> somebody gets the 1 unit, sum == 1
    a = Settlement.split_breakage(1, { "successPct" => 33, "platformPct" => 33, "institutionPct" => 34 })
    assert_equal 1, a.values.sum
    # 100 @ thirds
    b = Settlement.split_breakage(100, { "successPct" => 33.33, "platformPct" => 33.33, "institutionPct" => 33.34 })
    assert_equal 100, b.values.sum
    # property sweep
    [1, 2, 3, 7, 99, 101, 999, 5_000_001].each do |amt|
      s = Settlement.split_breakage(amt, SPLIT)
      assert_equal amt, s.values.sum, "amt=#{amt}"
    end
  end

  def test_idempotency_key_binds_version
    c = commitment(stake: 10_000_000, pct: 50, outcome: "unsuccessful")
    assert_equal "c1:settle:v1", Settlement.build_entries(c)["idempotencyKey"]
    c["rulesVersion"] = 2
    assert_equal "c1:settle:v2", Settlement.build_entries(c)["idempotencyKey"]
  end
end

# Stage 4+5 acceptance run. Usage: ruby apps/api/accept_stage45.rb <programme_id>
require "json"
require "net/http"

API = "http://localhost:3001"
P = ARGV[0] or abort "need programme id"
$fail = 0
def check(name, code, want)
  ok = code == want
  $fail += 1 unless ok
  puts "#{ok ? 'PASS' : 'FAIL'} #{name} (got #{code}, want #{want})"
end
def req(method, path, body = nil)
  uri = URI("#{API}#{path}")
  r = case method
      when :get then Net::HTTP.get_response(uri)
      when :post then Net::HTTP.post(uri, JSON.generate(body || {}), "Content-Type" => "application/json")
      end
  [r.code.to_i, (JSON.parse(r.body) rescue r.body)]
end

# guards
code, _ = req(:post, "/programmes/#{P}/enrol", { "userId" => "user-01" })
check("enrol without acceptance", code, 422)
code, _ = req(:post, "/programmes/#{P}/enrol", { "userId" => "user-01", "acceptedRulesVersion" => 99 })
check("enrol wrong version", code, 409)
code, _ = req(:post, "/programmes", { "institutionId" => "x", "name" => "Bad", "rules" => { "objective" => "x" } })
check("programme invalid rules/institution", code, 422)

# bulk lifecycle: even users succeed, odd fail
_, progress = req(:get, "/programmes/#{P}/progress")
progress.each do |c|
  n = c["userId"].split("-").last.to_i
  verdict = n.even? ? "successful" : "unsuccessful"
  req(:post, "/commitments/#{c["id"]}/activate")
  req(:post, "/commitments/#{c["id"]}/submit-for-verification")
  code, _ = req(:post, "/commitments/#{c["id"]}/verify", { "method" => "manual_review", "verdict" => verdict })
  check("verify #{c["userId"]} #{verdict}", code, 200)
  code, _ = req(:post, "/commitments/#{c["id"]}/settle", {})
  check("settle #{c["userId"]}", code, 200)
end

code, results = req(:get, "/programmes/#{P}/results")
check("results 200", code, 200)
puts "results: #{results}"
check("5 successful", results["successful"], 5)
check("5 unsuccessful", results["unsuccessful"], 5)
check("10 participants-commitments", results["commitments"], 10)
# 10 x 1,000,000 stake (10_000_00 minor units) = 10,000,000; 5 fail @50% -> forfeit 2,500,000
check("committed 10000000", results["committed"], 10_000_000)
check("forfeited 2500000", results["forfeited"], 2_500_000)
check("returned 7500000", results["returned"], 7_500_000)
check("pool 1750000", results["toSuccessPool"], 1_750_000)
check("platform 500000", results["toPlatform"], 500_000)
check("institution 250000", results["toInstitution"], 250_000)

# rules v2: old pinned, new enrol must accept v2
_, prog = req(:get, "/programmes/#{P}")
rules2 = prog["rulesVersions"][0]["rules"].merge("measurement" => "30 check-ins + final quiz")
code, v = req(:post, "/programmes/#{P}/rules", { "rules" => rules2 })
check("publish v2", code, 201)
code, _ = req(:post, "/programmes/#{P}/enrol", { "userId" => "demo-user", "acceptedRulesVersion" => 1 })
check("enrol stale v1 rejected", code, 409)
code, e = req(:post, "/programmes/#{P}/enrol", { "userId" => "demo-user", "acceptedRulesVersion" => 2 })
check("enrol v2 accepted", code, 201)
puts "demo-user pinned v#{e["rulesVersion"]} (want 2)"

# suspend blocks enrol
code, _ = req(:post, "/programmes/#{P}/suspend", {})
check("suspend 200", code, 200)
code, _ = req(:post, "/programmes/#{P}/enrol", { "userId" => "demo-user", "acceptedRulesVersion" => 2 })
check("enrol suspended rejected", code, 409)

# leaderboard + consent
code, lb = req(:get, "/programmes/#{P}/leaderboard")
check("leaderboard aggregate", code, 200)
puts "leaderboard: #{lb}"
code, _ = req(:post, "/programmes/#{P}/visibility", { "visibility" => "public" })
check("visibility public", code, 200)
code, lb2 = req(:get, "/programmes/#{P}/leaderboard")
anon = lb2["rows"].count { |r| r["user"] == "Anonymous" }
puts "public rows=#{lb2["rows"].length} anonymous=#{anon} (want 10 rows, 5 anon)"
check("public 10 rows", lb2["rows"].length, 10)
check("consent masking 5 anon", anon, 5)

# dashboard + reminders + history
code, dash = req(:get, "/dashboard/summary")
check("dashboard 200", code, 200)
puts "dashboard: #{dash}"
code, rem = req(:post, "/notifications/send-reminders", {})
check("reminders 200", code, 200)
puts "reminders sent=#{rem["sent"]}"
code, hist = req(:get, "/users/user-02/history")
check("private history 403 (no consent)", code, 403)
code, hist1 = req(:get, "/users/user-01/history")
check("consented history 200", code, 200)
puts "user-01 rate=#{hist1["stats"]["completionRate"]}%"

puts($fail.zero? ? "ALL ACCEPTANCE PASSED" : "#{$fail} FAILURES")
exit($fail.zero? ? 0 : 1)

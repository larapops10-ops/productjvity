# Stage 6 acceptance: disputes, exceptions, admin, audit.
# Usage: ruby apps/api/accept_stage6.rb
require "json"
require "net/http"

API = "http://localhost:3001"
$fail = 0
def check(name, got, want)
  ok = got == want
  $fail += 1 unless ok
  puts "#{ok ? 'PASS' : 'FAIL'} #{name} (got #{got.inspect}, want #{want.inspect})"
end
def req(method, path, body = nil)
  uri = URI("#{API}#{path}")
  r = case method
      when :get then Net::HTTP.get_response(uri)
      when :post then Net::HTTP.post(uri, JSON.generate(body || {}), "Content-Type" => "application/json")
      end
  [r.code.to_i, (JSON.parse(r.body) rescue r.body)]
end

# fresh commitment to dispute
code, c = req(:post, "/commitments", { "objective" => "Dispute me", "deadline" => "2026-10-30",
                                       "stakeAmount" => 10_000_000, "maxForfeiturePct" => 50 })
check("create", code, 201)
req(:post, "/commitments/#{c['id']}/activate")
req(:post, "/commitments/#{c['id']}/submit-for-verification")
req(:post, "/commitments/#{c['id']}/verify", { "method" => "self_attest", "verdict" => "unsuccessful" })
code, s = req(:post, "/commitments/#{c['id']}/settle", {})
check("settle", code, 200)
check("forfeited", s["allocation"]["toSuccessPool"] + s["allocation"]["toPlatform"] + s["allocation"]["toInstitution"], 5_000_000)

# dispute guards
code, _ = req(:post, "/disputes", { "commitmentId" => c["id"], "reason" => "made_up_reason" })
check("bad reason 422", code, 422)
code, d = req(:post, "/disputes", { "commitmentId" => c["id"], "reason" => "incorrect_verification" })
check("open dispute", code, 201)
check("status disputed", d["status"], "open")
code, _ = req(:post, "/disputes/#{d['id']}/review", { "status" => "resolved", "action" => "overturn", "verdict" => "successful" })
check("review 200", code, 200)

# overturn: re-verified + re-settled, old rows kept
code, o = req(:get, "/commitments/#{c['id']}/outcome")
check("outcome 200", code, 200)
check("net returned full stake", o["returned"], 10_000_000)
check("net forfeited 0", o["forfeited"], 0)
check("two settlement epochs", o["settlements"], 2)
check("verdict rows 2", o["ledger"].length, 10) # 5 + 5

# dispute on unsettled -> 409
code, c2 = req(:post, "/commitments", { "objective" => "No settle", "deadline" => "2026-10-30" })
req(:post, "/commitments/#{c2['id']}/activate")
code, _ = req(:post, "/disputes", { "commitmentId" => c2["id"], "reason" => "wrong_forfeiture" })
check("dispute unsettled 409", code, 409)

# exception flag
code, _ = req(:post, "/commitments/#{c2['id']}/exception", { "reason" => "payment provider outage" })
check("exception 200", code, 200)

# admin endpoints + audit
code, ov = req(:get, "/admin/overview")
check("overview 200", code, 200)
puts "overview: #{ov}"
check("audit entries > 0", ov["auditEntries"] > 0, true)
code, _ = req(:get, "/admin/audit")
check("audit 200", code, 200)
code, _ = req(:get, "/admin/disputes")
check("disputes 200", code, 200)
code, _ = req(:get, "/admin/ledger")
check("ledger 200", code, 200)
code, _ = req(:post, "/admin/institutions", { "institutionId" => "x", "status" => "suspended" })
check("admin bad institution 404", code, 404)

# non-admin guard (simulate by flipping role in db)
db_path = File.expand_path("../../data/db.json", __dir__)
db = JSON.parse(File.read(db_path))
db["users"].find { |u| u["id"] == "demo-user" }["role"] = "user"
File.write(db_path, JSON.pretty_generate(db))
code, _ = req(:get, "/admin/overview")
check("non-admin 403", code, 403)
db["users"].find { |u| u["id"] == "demo-user" }["role"] = "platform_admin"
File.write(db_path, JSON.pretty_generate(db))
code, _ = req(:get, "/admin/overview")
check("admin restored 200", code, 200)

puts($fail.zero? ? "ALL STAGE 6 ACCEPTANCE PASSED" : "#{$fail} FAILURES")
exit($fail.zero? ? 0 : 1)

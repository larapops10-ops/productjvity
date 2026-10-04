# Stage 4 acceptance seed: 10 test users + institution + programme + enrol all.
# Run: ruby apps/api/seed_stage4.rb  (API must be running on :3001)
require "json"
require "net/http"

API = "http://localhost:3001"
def post(path, body)
  uri = URI("#{API}#{path}")
  r = Net::HTTP.post(uri, JSON.generate(body), "Content-Type" => "application/json")
  [r.code.to_i, (JSON.parse(r.body) rescue r.body)]
end
def get(path)
  uri = URI("#{API}#{path}")
  r = Net::HTTP.get_response(uri)
  [r.code.to_i, (JSON.parse(r.body) rescue r.body)]
end

users = (1..10).map do |i|
  id = format("user-%02d", i)
  # register via db directly? No users endpoint for create (single-user demo), so inject:
  id
end
# Inject test users straight into the store through enrolments is not possible
# (enrol takes any userId string, no registry check) — create registry via file:
db_path = File.expand_path("../../data/db.json", __dir__)
db = JSON.parse(File.read(db_path))
db["users"] ||= []
db["institutions"] ||= []
db["programmes"] ||= []
db["notifications"] ||= []
db["ledger"] ||= []
db["breakage"] ||= []
users.each_with_index do |id, i|
  db["users"] << { "id" => id, "name" => "Test User #{i + 1}", "email" => "#{id}@example.com",
                   "role" => "user", "consentProfilePublic" => i.even? } unless db["users"].any? { |u| u["id"] == id }
end
File.write(db_path, JSON.pretty_generate(db))
puts "users: ok (10)"

_, inst = post("/institutions", { "name" => "Demo Church" })
puts "institution: #{inst["id"]}"

rules = {
  "objective" => "Read the Bible in 30 days", "startsAt" => "2026-10-01T00:00:00.000Z",
  "endsAt" => "2026-10-31T23:59:59.000Z", "measurement" => "30 daily check-ins",
  "evidenceRequired" => ["daily-checkin"], "successCriteria" => "30 check-ins by 31 Oct",
  "failureCriteria" => "Fewer than 30 check-ins", "stake" => { "amount" => 10_000_00, "currency" => "NGN" },
  "maxForfeiturePct" => 50, "rewardFormula" => "pro-rata success pool",
  "breakageSplit" => { "successPct" => 70, "platformPct" => 20, "institutionPct" => 10 },
  "platformFees" => "20% of forfeit", "exceptions" => "illness with note",
  "disputeProcess" => "raise within 7 days"
}
code, prog = post("/programmes", { "institutionId" => inst["id"], "name" => "October Challenge",
                                   "eligibility" => { "open" => true }, "rules" => rules })
abort "programme create failed: #{code} #{prog}" unless code == 201
puts "programme: #{prog["id"]} v#{prog["currentVersion"]}"

users.each do |u|
  code, _ = post("/programmes/#{prog["id"]}/enrol", { "userId" => u, "acceptedRulesVersion" => 1 })
  abort "enrol failed for #{u}: #{code}" unless code == 201
end
puts "enrolled: 10/10"
puts "PROGRAMME_ID=#{prog["id"]}"

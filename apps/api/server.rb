# Stage 2 API (Ruby stdlib). Contract: plan Stage 2 + STATE_MACHINE.md.
# Run: ruby apps/api/server.rb (PORT default 3001; store data/db.json).

require "webrick"
require "json"
require "securerandom"
require "fileutils"
require "date"
require "base64"
require "digest"
require_relative "../../packages/settlement/settle"

PORT  = (ENV["PORT"] || 3001).to_i
ROOT  = File.expand_path("../..", __dir__)
STORE = File.join(ROOT, "data", "db.json")
UPLOAD_DIR = File.join(ROOT, "uploads", "evidence")
MAX_EVIDENCE_BYTES = 5 * 1024 * 1024
EVIDENCE_TYPES = {
  "image/jpeg" => ".jpg",
  "image/png" => ".png",
  "image/webp" => ".webp",
  "application/pdf" => ".pdf"
}.freeze
FileUtils.mkdir_p(File.dirname(STORE))
FileUtils.mkdir_p(UPLOAD_DIR)

def load_db
  blank = { "commitments" => [], "ledger" => [], "breakage" => [],
            "users" => [{ "id" => "demo-user", "name" => "Lara", "email" => "lara@example.com",
                          "role" => "platform_admin", "consentProfilePublic" => false }],
            "institutions" => [], "programmes" => [], "notifications" => [],
            "disputes" => [], "audit" => [] }
  return blank unless File.exist?(STORE)
  db = JSON.parse(File.read(STORE))
  blank.merge(db)
rescue StandardError
  { "commitments" => [], "ledger" => [], "breakage" => [],
    "users" => [], "institutions" => [], "programmes" => [], "notifications" => [],
    "disputes" => [], "audit" => [] }
end

def save_db(db)
  File.write(STORE, JSON.pretty_generate(db))
end

def find_commitment(db, id)
  db["commitments"].find { |c| c["id"] == id }
end

def commitment_view(c)
  total = c["milestones"].length
  done  = c["milestones"].count { |m| m["done"] }
  c.merge("progressPct" => (total.zero? ? (c["status"] == "settled" ? 100 : 0) : (done * 100 / total)))
end

# --- rules snapshot pinned at creation (personal variant, PRD §11) ---
def default_rules(body)
  {
    "objective" => body["objective"],
    "startsAt" => Time.now.utc.iso8601,
    "endsAt" => body["deadline"],
    "measurement" => body["successCriteria"] || "Self-attested completion",
    "evidenceRequired" => [],
    "successCriteria" => body["successCriteria"] || "Marked complete by deadline",
    "failureCriteria" => "Not completed by deadline",
    "stake" => { "amount" => body["stakeAmount"] || 0, "currency" => body["currency"] || "NGN" },
    "maxForfeiturePct" => body["maxForfeiturePct"] || 0,
    "rewardFormula" => "points only (no money in Stage 2)",
    "breakageSplit" => body["breakageSplit"] || { "successPct" => 70, "platformPct" => 20, "institutionPct" => 10 },
    "platformFees" => "none in Stage 2",
    "exceptions" => "none",
    "disputeProcess" => "contact support"
  }
end

# --- Stage 4: institutions & programmes (PRD §7, §10) ---
RULES_REQUIRED = %w[objective startsAt endsAt measurement evidenceRequired successCriteria failureCriteria stake maxForfeiturePct rewardFormula breakageSplit platformFees exceptions disputeProcess].freeze

def validate_rules(r)
  errors = []
  RULES_REQUIRED.each { |k| errors << "missing: #{k}" if r[k].nil? || r[k] == "" }
  if r["stake"] && (!r["stake"]["amount"].is_a?(Numeric) || r["stake"]["amount"] < 0)
    errors << "stake.amount must be >= 0"
  end
  if r["maxForfeiturePct"] && (r["maxForfeiturePct"] < 0 || r["maxForfeiturePct"] > 100)
    errors << "maxForfeiturePct must be 0-100"
  end
  if (s = r["breakageSplit"])
    sum = (s["successPct"] || 0) + (s["platformPct"] || 0) + (s["institutionPct"] || 0)
    errors << "breakageSplit must sum to 100 (got #{sum})" if (sum - 100).abs > 1e-9
  end
  errors
end

def find_institution(db, id)
  (db["institutions"] || []).find { |i| i["id"] == id }
end

def find_programme(db, id)
  (db["programmes"] || []).find { |p| p["id"] == id }
end

def find_user(db, id)
  (db["users"] || []).find { |u| u["id"] == id }
end

def current_rules(programme)
  (programme["rulesVersions"] || []).max_by { |v| v["version"] }
end

def latest_breakage(db, commitment_id)
  ((db["breakage"] || []).select { |b| b["commitmentId"] == commitment_id }).last
end

def programme_results(db, programme)
  cs = (db["commitments"] || []).select { |c| c["programmeId"] == programme["id"] && c["status"] != "draft" }
  ok = cs.count { |c| c["outcome"] == "successful" }
  bad = cs.count { |c| c["outcome"] == "unsuccessful" }
  committed = cs.map { |c| c["stakeAmount"] || 0 }.sum
  br = cs.map { |c| latest_breakage(db, c["id"]) }.compact
  {
    "participants" => cs.map { |c| c["userId"] }.uniq.length,
    "commitments" => cs.length, "successful" => ok, "unsuccessful" => bad,
    "completionRate" => cs.empty? ? 0 : (ok * 100 / cs.length),
    "committed" => committed,
    "returned" => br.map { |b| b["returned"] }.sum,
    "forfeited" => br.map { |b| b["forfeited"] }.sum,
    "toSuccessPool" => br.map { |b| b["allocation"]["toSuccessPool"] }.sum,
    "toPlatform" => br.map { |b| b["allocation"]["toPlatform"] }.sum,
    "toInstitution" => br.map { |b| b["allocation"]["toInstitution"] }.sum
  }
end

# --- Stage 6: disputes, exceptions, admin (PRD §16, §18) ---
DISPUTE_REASONS = ["incorrect_verification", "technical_failure", "wrong_forfeiture",
                   "exceptional_circumstance", "payment_discrepancy"].freeze

def audit(db, actor_id, action, target_type, target_id, diff = {}, reason = nil)
  db["audit"] ||= []
  a = { "id" => SecureRandom.uuid, "actorId" => actor_id, "action" => action,
        "targetType" => target_type, "targetId" => target_id,
        "diff" => diff, "reason" => reason, "createdAt" => Time.now.utc.iso8601 }
  db["audit"] << a
  a
end

def admin?(db)
  u = (db["users"] || []).find { |x| x["id"] == "demo-user" }
  u && u["role"] == "platform_admin"
end

# --- Stage 5: notifications (§13) ---
def notify(db, user_id, template, commitment_id, payload = {})
  db["notifications"] ||= []
  day = Time.now.utc.strftime("%Y-%m-%d")
  dup = db["notifications"].any? { |n| n["userId"] == user_id && n["template"] == template && n["commitmentId"] == commitment_id && n["day"] == day }
  return nil if dup
  n = { "id" => SecureRandom.uuid, "userId" => user_id, "template" => template,
        "commitmentId" => commitment_id, "payload" => payload, "day" => day, "sentAt" => Time.now.utc.iso8601 }
  db["notifications"] << n
  n
end

server = WEBrick::HTTPServer.new(Port: PORT, AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN))

# CORS for apps/web on :8080 + file:// preview
def cors(res)
  res["Access-Control-Allow-Origin"] = "*"
  res["Access-Control-Allow-Methods"] = "GET, POST, PATCH, OPTIONS"
  res["Access-Control-Allow-Headers"] = "Content-Type, Idempotency-Key"
end

def json(res, code, obj)
  cors(res)
  res.status = code
  res["Content-Type"] = "application/json"
  res.body = JSON.generate(obj)
end

def read_body(req)
  return {} if req.body.nil? || req.body.empty?
  JSON.parse(req.body)
rescue StandardError
  {}
end

def save_evidence_file(body, existing_evidence = [])
  content_type = body["contentType"]
  extension = EVIDENCE_TYPES[content_type]
  return [nil, "Only JPG, PNG, WebP, and PDF files are allowed"] if extension.nil?

  encoded = body["dataBase64"].to_s
  return [nil, "file data is required"] if encoded.empty?
  return [nil, "Files must be 5 MB or smaller"] if encoded.bytesize > (MAX_EVIDENCE_BYTES * 4 / 3) + 8

  bytes = Base64.strict_decode64(encoded)
  return [nil, "Files must be 5 MB or smaller"] if bytes.bytesize > MAX_EVIDENCE_BYTES
  fingerprint = Digest::SHA256.hexdigest(bytes)
  if existing_evidence.any? { |e| e["sha256"] == fingerprint }
    return [nil, "This exact proof file was already uploaded"]
  end

  key = "#{SecureRandom.uuid}#{extension}"
  File.binwrite(File.join(UPLOAD_DIR, key), bytes)
  [{ "storageKey" => key, "fileUrl" => "/uploads/evidence/#{key}",
     "contentType" => content_type, "sizeBytes" => bytes.bytesize,
     "sha256" => fingerprint }, nil]
rescue ArgumentError
  [nil, "The uploaded file could not be read"]
end

server.mount_proc("/") do |req, res|
  cors(res)
  if req.request_method == "OPTIONS"
    res.status = 204
    next
  end

  db = load_db
  parts = req.path.sub(%r{^/}, "").split("/")
  body = read_body(req)

  case [req.request_method, parts[0]]
  when ["GET", "uploads"]
    # Local development storage. Production will use private, short-lived
    # object-storage URLs once authentication is in place.
    key = parts[2].to_s
    path = File.expand_path(File.join(UPLOAD_DIR, key))
    unless parts.length == 3 && key.match?(/\A[0-9a-f-]+\.(jpg|png|webp|pdf)\z/) && path.start_with?(UPLOAD_DIR + "/") && File.file?(path)
      json(res, 404, { error: "evidence-not-found" })
      next
    end
    res.status = 200
    res["Content-Type"] = EVIDENCE_TYPES.invert[File.extname(key)] || "application/octet-stream"
    res["Content-Disposition"] = "inline"
    res.body = File.binread(path)
  when ["GET", nil], ["GET", ""]
    # Same-origin UI (avoids CORS / second-origin browser issues entirely).
    page = File.join(ROOT, "apps", "web", "index.html")
    if File.exist?(page)
      res.status = 200
      res["Content-Type"] = "text/html; charset=utf-8"
      res.body = File.read(page)
    else
      json(res, 200, { service: "productjvity-api", stage: 3 })
    end
  when ["GET", "health"]
    json(res, 200, { ok: true, stage: 3 })
  when ["GET", "commitments"]
    if parts.length == 1
      json(res, 200, db["commitments"].map { |c| commitment_view(c) })
    elsif parts.length == 2
      c = find_commitment(db, parts[1])
      c ? json(res, 200, commitment_view(c)) : json(res, 404, { error: "not-found" })
    elsif parts.length == 3 && parts[2] == "outcome"
      # Receipt (PRD §15): full breakdown + pinned rules version.
      # Net-aggregated so dispute reversals (Stage 6) are reflected.
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif c["status"] != "settled"
        json(res, 409, { error: "not settled yet", status: c["status"] })
      else
        rows = (db["ledger"] || []).select { |l| l["commitmentId"] == c["id"] }
        net = ->(t) { rows.select { |l| l["type"] == t }.map { |l| l["amount"] }.sum }
        allocs = (db["breakage"] || []).select { |b| b["commitmentId"] == c["id"] }
        alloc = allocs.last ? allocs.last["allocation"] : { "toSuccessPool" => 0, "toPlatform" => 0, "toInstitution" => 0 }
        json(res, 200, {
          "commitmentId" => c["id"], "objective" => c["objective"],
          "status" => c["status"], "outcome" => c["outcome"],
          "committed" => c["stakeAmount"], "currency" => c["currency"],
          "atRisk" => (c["stakeAmount"] * (c["rules"]["maxForfeiturePct"] || 0) / 100.0).round,
          "returned" => net.call("return"), "forfeited" => net.call("forfeit"),
          "allocation" => alloc, "rulesVersion" => c["rulesVersion"],
          "settlements" => allocs.length, "ledger" => rows
        })
      end
    else
      json(res, 404, { error: "not-found" })
    end
  when ["GET", "ledger.csv"]
    # CSV export of the simulated ledger (Stage 3 acceptance).
    lines = ["commitment_id,type,amount,currency,idempotency_key,created_at"]
    (db["ledger"] || []).each do |l|
      lines << [l["commitmentId"], l["type"], l["amount"], l["currency"], l["idempotencyKey"], l["createdAt"]].join(",")
    end
    cors(res)
    res.status = 200
    res["Content-Type"] = "text/csv"
    res.body = lines.join("\n") + "\n"
  # --- Stage 6: disputes, exceptions, admin (PRD §16, §18) ---
  when ["GET", "disputes"], ["POST", "disputes"]
    if req.request_method == "GET"
      json(res, 200, db["disputes"] || [])
    else
      c = find_commitment(db, parts[1] || body["commitmentId"].to_s)
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif !DISPUTE_REASONS.include?(body["reason"])
        json(res, 422, { error: "reason must be one of #{DISPUTE_REASONS.join(', ')}" })
      elsif c["status"] != "settled"
        json(res, 409, { error: "only settled commitments can be disputed", status: c["status"] })
      else
        d = { "id" => SecureRandom.uuid, "commitmentId" => c["id"], "reporterId" => "demo-user",
              "reason" => body["reason"], "status" => "open", "resolution" => nil,
              "createdAt" => Time.now.utc.iso8601 }
        db["disputes"] << d
        c["status"] = "disputed"
        audit(db, "demo-user", "dispute.open", "commitment", c["id"], { "reason" => body["reason"] })
        notify(db, c["userId"], "dispute_opened", c["id"], { "reason" => body["reason"] })
        save_db(db)
        json(res, 201, d)
      end
    end
  when ["POST", "disputes"]
    if parts.length == 3 && parts[2] == "review"
      d = (db["disputes"] || []).find { |x| x["id"] == parts[1] }
      if d.nil?
        json(res, 404, { error: "not-found" })
      elsif !admin?(db)
        json(res, 403, { error: "platform_admin required" })
      elsif !%w[resolved rejected].include?(body["status"])
        json(res, 422, { error: "status must be resolved or rejected" })
      else
        c = find_commitment(db, d["commitmentId"])
        d["status"] = body["status"]
        d["resolution"] = body["resolution"]
        d["reviewedAt"] = Time.now.utc.iso8601
        audit(db, "demo-user", "dispute.#{body['status']}", "commitment", c["id"],
              { "reason" => d["reason"], "resolution" => body["resolution"] }, body["reason"])
        if body["status"] == "resolved" && body["action"] == "overturn"
          # Re-verify + re-settle with fresh epoch keys; old rows kept (never deleted).
          c["status"] = "pending_verification"
          c["verifications"] << { "id" => SecureRandom.uuid, "method" => "manual_review",
                                  "verdict" => body["verdict"] || "successful", "reason" => "dispute overturn",
                                  "decidedBy" => "demo-user", "decidedAt" => Time.now.utc.iso8601 }
          c["status"] = body["verdict"] || "successful"
          c["outcome"] = c["status"]
          c["settlementEpoch"] = (c["settlementEpoch"] || 0) + 1
          plan = Settlement.build_entries(c, c["settlementEpoch"])
          now = Time.now.utc.iso8601
          plan["entries"].each do |e|
            db["ledger"] << { "id" => SecureRandom.uuid, "commitmentId" => c["id"], "type" => e["type"],
                              "amount" => e["amount"], "currency" => c["currency"],
                              "idempotencyKey" => e["idempotencyKey"], "createdAt" => now }
          end
          db["breakage"] << { "commitmentId" => c["id"], "returned" => plan["returned"],
                              "forfeited" => plan["forfeited"], "allocation" => plan["allocation"], "createdAt" => now }
          c["status"] = "settled"
          notify(db, c["userId"], "dispute_resolved", c["id"], { "action" => "overturn" })
        elsif body["status"] == "resolved" && body["action"] == "uphold"
          c["status"] = "settled"
          notify(db, c["userId"], "dispute_resolved", c["id"], { "action" => "uphold" })
        end
        save_db(db)
        json(res, 200, d)
      end
    else
      json(res, 404, { error: "not-found" })
    end
  when ["POST", "commitments"]
    if parts.length == 3 && parts[2] == "exception"
      # Technical failure: pause deadline, flag for review (PRD §16).
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      else
        c["exception"] = { "flagged" => true, "reason" => body["reason"], "flaggedAt" => Time.now.utc.iso8601 }
        audit(db, "demo-user", "commitment.exception", "commitment", c["id"], {}, body["reason"])
        save_db(db)
        json(res, 200, commitment_view(c))
      end
    elsif parts.length == 3 && parts[2] == "admin-override"
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif !admin?(db)
        json(res, 403, { error: "platform_admin required" })
      else
        c["status"] = body["status"]
        c["outcome"] = body["outcome"] if body["outcome"]
        audit(db, "demo-user", "commitment.admin-override", "commitment", c["id"],
              { "from" => c["status"], "to" => body["status"] }, body["reason"])
        save_db(db)
        json(res, 200, commitment_view(c))
      end
    elsif parts.length == 1
      # Create draft (wizard step: goal + deadline + optional criteria/stake)
      if body["objective"].to_s.strip.empty? || body["deadline"].to_s.strip.empty?
        json(res, 422, { error: "objective and deadline are required" })
        next
      end
      c = {
        "id" => SecureRandom.uuid,
        "userId" => "demo-user", # auth deferred (Stage 6); single-user scope for now
        "programmeId" => nil,
        "rulesVersion" => 1,
        "rules" => default_rules(body),
        "objective" => body["objective"].strip,
        "deadline" => body["deadline"],
        "stakeAmount" => body["stakeAmount"] || 0,
        "currency" => body["currency"] || "NGN",
        "status" => "draft",
        "outcome" => nil,
        "milestones" => [],
        "evidence" => [],
        "verifications" => [],
        "createdAt" => Time.now.utc.iso8601
      }
      db["commitments"] << c
      save_db(db)
      json(res, 201, commitment_view(c))
    elsif parts.length == 3 && parts[2] == "activate"
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif c["status"] != "draft"
        json(res, 409, { error: "only draft can be activated", status: c["status"] })
      else
        c["status"] = "active" # pins rulesVersion/Rules snapshot
        save_db(db)
        json(res, 200, commitment_view(c))
      end
    elsif parts.length == 3 && parts[2] == "milestones"
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif body["title"].to_s.strip.empty?
        json(res, 422, { error: "title is required" })
      else
        m = { "id" => SecureRandom.uuid, "title" => body["title"].strip, "dueAt" => body["dueAt"], "required" => true, "done" => false }
        c["milestones"] << m
        save_db(db)
        json(res, 201, m)
      end
    elsif parts.length == 3 && parts[2] == "evidence"
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif c["status"] != "active"
        json(res, 409, { error: "evidence can only be added while a commitment is active", status: c["status"] })
      else
        saved, error = save_evidence_file(body, c["evidence"] || [])
        if error
          json(res, 422, { error: error })
        else
          file_name = File.basename(body["fileName"].to_s).strip
          e = saved.merge(
            "id" => SecureRandom.uuid,
            "fileName" => (file_name.empty? ? "evidence#{File.extname(saved['storageKey'])}" : file_name),
            "note" => body["note"].to_s.strip,
            "submittedAt" => Time.now.utc.iso8601
          )
          c["evidence"] << e
          save_db(db)
          json(res, 201, e)
        end
      end
    elsif parts.length == 3 && parts[2] == "submit-for-verification"
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif c["status"] != "active"
        json(res, 409, { error: "only active can be submitted", status: c["status"] })
      else
        c["status"] = "pending_verification"
        save_db(db)
        json(res, 200, commitment_view(c))
      end
    elsif parts.length == 3 && parts[2] == "verify"
      # Verification v0: self_attest | manual_review. Decision rows immutable.
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif c["status"] != "pending_verification"
        json(res, 409, { error: "only pending_verification can be verified", status: c["status"] })
      elsif !%w[self_attest manual_review].include?(body["method"])
        json(res, 422, { error: "method must be self_attest or manual_review" })
      elsif !%w[successful unsuccessful].include?(body["verdict"])
        json(res, 422, { error: "verdict must be successful or unsuccessful" })
      else
        c["verifications"] << { "id" => SecureRandom.uuid, "method" => body["method"], "verdict" => body["verdict"], "reason" => body["reason"], "decidedBy" => "demo-user", "decidedAt" => Time.now.utc.iso8601 }
        c["status"] = body["verdict"]
        c["outcome"] = body["verdict"]
        save_db(db)
        json(res, 200, commitment_view(c))
      end
    elsif parts.length == 3 && parts[2] == "settle"
      # Simulated settlement (Stage 3). Idempotent: repeat returns existing.
      c = find_commitment(db, parts[1])
      existing = c && latest_breakage(db, c["id"])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif existing && c["status"] == "settled"
        rows = (db["ledger"] || []).select { |l| l["commitmentId"] == c["id"] }
        json(res, 200, { "settled" => true, "repeated" => true, "ledger" => rows, "allocation" => existing["allocation"] })
      elsif !%w[successful unsuccessful].include?(c["status"])
        json(res, 409, { error: "only verified commitments can settle", status: c["status"] })
      else
        plan = Settlement.build_entries(c)
        now = Time.now.utc.iso8601
        plan["entries"].each do |e|
          db["ledger"] << { "id" => SecureRandom.uuid, "commitmentId" => c["id"], "type" => e["type"],
                            "amount" => e["amount"], "currency" => c["currency"],
                            "idempotencyKey" => e["idempotencyKey"], "createdAt" => now }
        end
        db["breakage"] << { "commitmentId" => c["id"], "returned" => plan["returned"],
                            "forfeited" => plan["forfeited"], "allocation" => plan["allocation"], "createdAt" => now }
        c["status"] = "settled"
        notify(db, c["userId"], "completion", c["id"], { "outcome" => c["outcome"] })
        if plan["forfeited"].positive?
          notify(db, c["userId"], "forfeiture", c["id"], { "amount" => plan["forfeited"] })
        else
          notify(db, c["userId"], "reward", c["id"], { "returned" => plan["returned"] })
        end
        save_db(db)
        rows = db["ledger"].select { |l| l["commitmentId"] == c["id"] }
        json(res, 200, { "settled" => true, "repeated" => false, "ledger" => rows, "allocation" => plan["allocation"] })
      end
    elsif parts.length == 3 && parts[2] == "rules"
      # Retrospective rule-edit guard (PRD §6.4): rules mutable in draft only.
      # POST (not PATCH) because WEBrick ProcHandler has no do_PATCH.
      c = find_commitment(db, parts[1])
      if c.nil?
        json(res, 404, { error: "not-found" })
      elsif c["status"] != "draft"
        json(res, 409, { error: "rules are pinned after activation; create a new version instead", status: c["status"] })
      else
        c["rules"] = c["rules"].merge(body)
        save_db(db)
        json(res, 200, commitment_view(c))
      end
    elsif parts.length == 5 && parts[2] == "milestones" && parts[4] == "toggle"
      id = parts[1]; mid = parts[3]
      c = find_commitment(db, id)
      m = c && c["milestones"].find { |x| x["id"] == mid }
      if m.nil?
        json(res, 404, { error: "not-found" })
      else
        m["done"] = body.key?("done") ? !!body["done"] : !m["done"]
        save_db(db)
        json(res, 200, m)
      end
    else
      json(res, 404, { error: "not-found" })
    end
  # --- Stage 4: institutions & programmes ---
  when ["GET", "admin"]
    if parts.length == 2 && parts[1] == "overview"
      unless admin?(db)
        json(res, 403, { error: "platform_admin required" })
      else
        json(res, 200, {
          "users" => (db["users"] || []).length,
          "institutions" => (db["institutions"] || []).length,
          "programmes" => (db["programmes"] || []).length,
          "commitments" => (db["commitments"] || []).length,
          "disputes" => (db["disputes"] || []).length,
          "openDisputes" => (db["disputes"] || []).count { |d| d["status"] == "open" },
          "auditEntries" => (db["audit"] || []).length,
          "ledgerRows" => (db["ledger"] || []).length
        })
      end
    elsif parts.length == 2 && parts[1] == "ledger"
      unless admin?(db)
        json(res, 403, { error: "platform_admin required" })
      else
        json(res, 200, db["ledger"] || [])
      end
    elsif parts.length == 2 && parts[1] == "disputes"
      unless admin?(db)
        json(res, 403, { error: "platform_admin required" })
      else
        json(res, 200, (db["disputes"] || []).map { |d| d.merge("commitment" => find_commitment(db, d["commitmentId"]) || {}) })
      end
    elsif parts.length == 2 && parts[1] == "audit"
      unless admin?(db)
        json(res, 403, { error: "platform_admin required" })
      else
        json(res, 200, (db["audit"] || []).reverse)
      end
    elsif parts.length == 2 && parts[1] == "institutions"
      unless admin?(db)
        json(res, 403, { error: "platform_admin required" })
      else
        json(res, 200, (db["institutions"] || []).map { |i| i.merge("status" => body["status"] || i["status"]) })
      end
    else
      json(res, 404, { error: "not-found" })
    end
  when ["POST", "admin"]
    if parts.length == 2 && parts[1] == "institutions"
      inst = find_institution(db, body["institutionId"].to_s)
      if inst.nil?
        json(res, 404, { error: "not-found" })
      elsif !admin?(db)
        json(res, 403, { error: "platform_admin required" })
      elsif !%w[active suspended].include?(body["status"])
        json(res, 422, { error: "status must be active or suspended" })
      else
        old = inst["status"]
        inst["status"] = body["status"]
        audit(db, "demo-user", "institution.#{body['status']}", "institution", inst["id"], { "from" => old, "to" => body["status"] }, body["reason"])
        save_db(db)
        json(res, 200, inst)
      end
    else
      json(res, 404, { error: "not-found" })
    end
  when ["GET", "institutions"], ["POST", "institutions"]
    if req.request_method == "GET"
      json(res, 200, db["institutions"] || [])
    else
      if body["name"].to_s.strip.empty?
        json(res, 422, { error: "name is required" })
      else
        i = { "id" => SecureRandom.uuid, "name" => body["name"].strip,
              "ownerId" => "demo-user", "status" => "active", "createdAt" => Time.now.utc.iso8601 }
        db["institutions"] << i
        save_db(db)
        json(res, 201, i)
      end
    end
  when ["GET", "programmes"], ["POST", "programmes"]
    if req.request_method == "GET" && parts.length == 2
      p = find_programme(db, parts[1])
      p ? json(res, 200, p.merge("currentVersion" => current_rules(p)["version"], "results" => programme_results(db, p)))
        : json(res, 404, { error: "not-found" })
    elsif req.request_method == "GET" && parts.length == 3 && parts[2] == "progress"
      p = find_programme(db, parts[1])
      if p.nil?
        json(res, 404, { error: "not-found" })
      else
        cs = (db["commitments"] || []).select { |c| c["programmeId"] == p["id"] }
        json(res, 200, cs.map { |c| commitment_view(c).merge("userId" => c["userId"]) })
      end
    elsif req.request_method == "GET" && parts.length == 3 && parts[2] == "results"
      p = find_programme(db, parts[1])
      p ? json(res, 200, programme_results(db, p)) : json(res, 404, { error: "not-found" })
    elsif req.request_method == "GET" && parts.length == 3 && parts[2] == "leaderboard"
      # §12 privacy: aggregate (default) | public (consent-masked names) | private (owner only)
      p = find_programme(db, parts[1])
      if p.nil?
        json(res, 404, { error: "not-found" })
      else
        cs = (db["commitments"] || []).select { |c| c["programmeId"] == p["id"] && c["status"] != "draft" }
        vis = p["visibility"] || "aggregate"
        if vis == "private" && p["institutionId"] && (find_institution(db, p["institutionId"]) || {})["ownerId"] != "demo-user"
          json(res, 403, { error: "private leaderboard" })
        elsif vis == "public"
          rows = cs.map do |c|
            u = find_user(db, c["userId"]) || { "name" => c["userId"] }
            { "user" => (u["consentProfilePublic"] ? (u["name"] || u["id"]) : "Anonymous"),
              "progressPct" => commitment_view(c)["progressPct"], "status" => c["status"] }
          end
          json(res, 200, { "mode" => vis, "rows" => rows })
        else
          json(res, 200, { "mode" => "aggregate", "participants" => cs.map { |c| c["userId"] }.uniq.length,
                           "avgProgress" => (cs.empty? ? 0 : (cs.map { |c| commitment_view(c)["progressPct"] }.sum / cs.length)),
                           "completed" => cs.count { |c| %w[successful unsuccessful settled].include?(c["status"]) } })
        end
      end
    elsif req.request_method == "GET"
      json(res, 200, (db["programmes"] || []).map { |p| p.merge("currentVersion" => current_rules(p)["version"], "results" => programme_results(db, p)) })
    elsif req.request_method == "POST" && parts.length == 3 && parts[2] == "enrol"
      # Join requires explicit acceptance of the CURRENT rules version (PRD §10).
      p = find_programme(db, parts[1])
      if p.nil?
        json(res, 404, { error: "not-found" })
      elsif p["status"] != "active"
        json(res, 409, { error: "programme is not accepting enrolments", status: p["status"] })
      elsif body["acceptedRulesVersion"].nil?
        json(res, 422, { error: "acceptedRulesVersion is required (accept the rules to join)" })
      elsif body["acceptedRulesVersion"] != current_rules(p)["version"]
        json(res, 409, { error: "rules changed; accept current version", currentVersion: current_rules(p)["version"] })
      else
        uid = body["userId"] || "demo-user"
        snap = current_rules(p)["rules"]
        c = { "id" => SecureRandom.uuid, "userId" => uid, "programmeId" => p["id"],
              "rulesVersion" => current_rules(p)["version"], "rules" => snap,
              "objective" => snap["objective"], "deadline" => snap["endsAt"],
              "stakeAmount" => (snap["stake"] || {})["amount"] || 0,
              "currency" => (snap["stake"] || {})["currency"] || "NGN",
              "status" => "draft", "outcome" => nil,
              "milestones" => [], "evidence" => [], "verifications" => [],
              "createdAt" => Time.now.utc.iso8601 }
        db["commitments"] << c
        save_db(db)
        json(res, 201, commitment_view(c))
      end
    elsif req.request_method == "POST" && parts.length == 3 && parts[2] == "rules"
      # New rules version; in-flight commitments keep their pinned version (PRD §6.4).
      p = find_programme(db, parts[1])
      errs = validate_rules(body["rules"] || {})
      if p.nil?
        json(res, 404, { error: "not-found" })
      elsif errs.any?
        json(res, 422, { error: "invalid rules", details: errs })
      else
        v = current_rules(p)["version"] + 1
        p["rulesVersions"] << { "version" => v, "rules" => body["rules"], "effectiveFrom" => Time.now.utc.iso8601 }
        save_db(db)
        json(res, 201, { "version" => v })
      end
    elsif req.request_method == "POST" && parts.length == 3 && parts[2] == "suspend"
      p = find_programme(db, parts[1])
      if p.nil?
        json(res, 404, { error: "not-found" })
      else
        p["status"] = "suspended"
        save_db(db)
        json(res, 200, { "id" => p["id"], "status" => p["status"] })
      end
    elsif req.request_method == "POST" && parts.length == 3 && parts[2] == "visibility"
      p = find_programme(db, parts[1])
      if p.nil?
        json(res, 404, { error: "not-found" })
      elsif !%w[private aggregate public].include?(body["visibility"])
        json(res, 422, { error: "visibility must be private, aggregate or public" })
      else
        p["visibility"] = body["visibility"]
        save_db(db)
        json(res, 200, { "id" => p["id"], "visibility" => p["visibility"] })
      end
    elsif req.request_method == "POST" && parts.length == 1
      inst = find_institution(db, body["institutionId"].to_s)
      errs = validate_rules(body["rules"] || {})
      if inst.nil?
        json(res, 422, { error: "valid institutionId is required" })
      elsif body["name"].to_s.strip.empty?
        json(res, 422, { error: "name is required" })
      elsif errs.any?
        json(res, 422, { error: "invalid rules", details: errs })
      else
        rules = body["rules"]
        p = { "id" => SecureRandom.uuid, "institutionId" => inst["id"],
              "name" => body["name"].strip, "objective" => rules["objective"],
              "startsAt" => rules["startsAt"], "endsAt" => rules["endsAt"],
              "eligibility" => body["eligibility"] || {}, "status" => "active",
              "visibility" => "aggregate",
              "rulesVersions" => [{ "version" => 1, "rules" => rules, "effectiveFrom" => Time.now.utc.iso8601 }],
              "createdAt" => Time.now.utc.iso8601 }
        db["programmes"] << p
        save_db(db)
        json(res, 201, p.merge("currentVersion" => 1))
      end
    else
      json(res, 404, { error: "not-found" })
    end
  when ["GET", "dashboard"]
    if parts == ["dashboard", "summary"]
      uid = "demo-user"
      mine = (db["commitments"] || []).select { |c| c["userId"] == uid && c["status"] != "draft" }
      act = mine.select { |c| %w[active pending_verification].include?(c["status"]) }
      done = mine.select { |c| %w[successful unsuccessful settled].include?(c["status"]) }
      br = mine.map { |c| latest_breakage(db, c["id"]) }.compact
      upcoming = act.map { |c| { "id" => c["id"], "objective" => c["objective"], "deadline" => c["deadline"] } }
                     .sort_by { |x| x["deadline"].to_s }.first(5)
      json(res, 200, {
        "active" => act.length, "completed" => done.length,
        "completionRate" => mine.empty? ? 0 : (done.count { |c| c["outcome"] == "successful" } * 100 / mine.length),
        "committed" => mine.map { |c| c["stakeAmount"] || 0 }.sum,
        "returned" => br.map { |b| b["returned"] }.sum,
        "forfeited" => br.map { |b| b["forfeited"] }.sum,
        "notifications" => (db["notifications"] || []).count { |n| n["userId"] == uid },
        "upcoming" => upcoming
      })
    else
      json(res, 404, { error: "not-found" })
    end
  when ["GET", "notifications"], ["POST", "notifications"]
    if parts == ["notifications", "send-reminders"] || (parts[0] == "notifications" && parts[1] == "send-reminders")
      sent = []
      (db["commitments"] || []).each do |c|
        next unless c["status"] == "active"
        days = ((Date.parse(c["deadline"].to_s) - Date.today).to_i rescue nil)
        next if days.nil?
        if days < 0
          n = notify(db, c["userId"], "overdue", c["id"], { "deadline" => c["deadline"] })
          sent << n if n
        elsif days <= 7
          n = notify(db, c["userId"], "deadline_soon", c["id"], { "daysLeft" => days })
          sent << n if n
        end
      end
      (db["commitments"] || []).each do |c|
        if c["status"] == "pending_verification"
          n = notify(db, c["userId"], "verification_request", c["id"], {})
          sent << n if n
        end
      end
      save_db(db)
      json(res, 200, { "sent" => sent.length, "notifications" => sent })
    elsif req.request_method == "GET"
      uid = body["userId"] || "demo-user"
      list = ((db["notifications"] || []).select { |n| n["userId"] == uid }).reverse
      json(res, 200, list)
    else
      json(res, 404, { error: "not-found" })
    end
  when ["GET", "users"]
    if parts.length == 3 && parts[2] == "history"
      u = find_user(db, parts[1])
      if u.nil?
        json(res, 404, { error: "not-found" })
      elsif u["id"] != "demo-user" && !u["consentProfilePublic"]
        json(res, 403, { error: "profile is private (no consent)" })
      else
        cs = (db["commitments"] || []).select { |c| c["userId"] == u["id"] }
        json(res, 200, {
          "user" => { "id" => u["id"], "name" => u["name"], "role" => u["role"] },
          "stats" => { "commitments" => cs.length,
                       "successful" => cs.count { |c| c["outcome"] == "successful" },
                       "completionRate" => cs.empty? ? 0 : (cs.count { |c| c["outcome"] == "successful" } * 100 / cs.length) },
          "commitments" => cs.map { |c| commitment_view(c) }
        })
      end
    else
      json(res, 200, db["users"] || [])
    end
  when ["POST", "users"]
    if parts.length == 3 && parts[2] == "consent"
      u = find_user(db, parts[1])
      if u.nil?
        json(res, 404, { error: "not-found" })
      else
        u["consentProfilePublic"] = !!body["consentProfilePublic"]
        save_db(db)
        json(res, 200, { "id" => u["id"], "consentProfilePublic" => u["consentProfilePublic"] })
      end
    else
      json(res, 404, { error: "not-found" })
    end
  else
    json(res, 404, { error: "not-found" })
  end
end

trap("INT") { server.shutdown }
puts "productjvity-api stage 2 on #{PORT} (store: #{STORE})"
server.start

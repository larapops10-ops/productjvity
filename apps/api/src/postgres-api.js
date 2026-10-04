import { createHash, pbkdf2Sync, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pool } from "./database.js";
import { buildSettlement } from "./settlement.js";
import { queueAiAssistedReview } from "./ai-review.js";

const PASSWORD_ITERATIONS = 210_000;
const SESSION_LIFETIME_SECONDS = 60 * 60 * 24 * 14;
const MAX_EVIDENCE_BYTES = 5 * 1024 * 1024;
const EVIDENCE_TYPES = { "image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf" };
const here = resolve(fileURLToPath(new URL(".", import.meta.url)));
const uploadDirectory = resolve(here, "../../../uploads/evidence");

const publicUser = (row) => ({
  id: row.id, email: row.email, name: row.name, role: row.role,
  consentProfilePublic: row.consent_profile_public, createdAt: row.created_at
});

const defaultRules = (body) => ({
  objective: body.objective,
  startsAt: new Date().toISOString(),
  endsAt: body.deadline,
  measurement: body.successCriteria || "Self-attested completion",
  evidenceRequired: [],
  successCriteria: body.successCriteria || "Marked complete by deadline",
  failureCriteria: "Not completed by deadline",
  stake: { amount: body.stakeAmount || 0, currency: body.currency || "NGN" },
  maxForfeiturePct: body.maxForfeiturePct || 0,
  rewardFormula: "points only (no money in prototype)",
  breakageSplit: body.breakageSplit || { successPct: 70, platformPct: 20, institutionPct: 10 },
  platformFees: "none in prototype", exceptions: "none", disputeProcess: "contact support"
});

function passwordRecord(password) {
  const salt = randomBytes(16);
  const digest = pbkdf2Sync(password, salt, PASSWORD_ITERATIONS, 32, "sha256");
  return { salt: salt.toString("base64"), digest: digest.toString("base64") };
}

function passwordMatches(password, record) {
  if (!record?.salt || !record?.digest) return false;
  const expected = Buffer.from(record.digest, "base64");
  const actual = pbkdf2Sync(password, Buffer.from(record.salt, "base64"), PASSWORD_ITERATIONS, expected.length, "sha256");
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 6 * 1024 * 1024) reject(new Error("Request is too large"));
    });
    req.on("end", () => {
      if (!raw) return resolve({});
      try { resolve(JSON.parse(raw)); } catch { reject(new Error("Invalid JSON body")); }
    });
    req.on("error", reject);
  });
}

export async function currentUser(req) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const digest = createHash("sha256").update(token).digest("hex");
  const result = await pool.query(`select u.* from sessions s join users u on u.id = s.user_id
    where s.token_digest = $1 and s.expires_at > now()`, [digest]);
  return result.rows[0] || null;
}

async function issueSession(userId) {
  const token = randomBytes(32).toString("base64url");
  const digest = createHash("sha256").update(token).digest("hex");
  await pool.query(`insert into sessions (id,user_id,token_digest,expires_at)
    values ($1,$2,$3,now() + ($4 * interval '1 second'))`, [randomUUID(), userId, digest, SESSION_LIFETIME_SECONDS]);
  return token;
}

async function commitmentView(row) {
  const [milestones, evidence, verifications] = await Promise.all([
    pool.query("select id,title,due_at,required,done from milestones where commitment_id=$1 order by created_at", [row.id]),
    pool.query("select id,milestone_id,storage_key,file_url,content_type,size_bytes,sha256,note,submitted_at from evidence where commitment_id=$1 order by submitted_at", [row.id]),
    pool.query("select id,method,verdict,reason,decided_by_id,decided_at from verification_decisions where commitment_id=$1 order by decided_at", [row.id])
  ]);
  const done = milestones.rows.filter((milestone) => milestone.done).length;
  const progressPct = milestones.rows.length ? Math.floor((done * 100) / milestones.rows.length) : row.status === "settled" ? 100 : 0;
  return {
    id: row.id, userId: row.user_id, programmeId: row.programme_id, rulesVersion: row.rules_version,
    rules: row.rules, objective: row.objective, deadline: row.deadline, stakeAmount: Number(row.stake_amount),
    currency: row.currency.trim(), status: row.status, outcome: row.outcome, createdAt: row.created_at,
    milestones: milestones.rows.map((m) => ({ id: m.id, title: m.title, dueAt: m.due_at, required: m.required, done: m.done })),
    evidence: evidence.rows.map((e) => ({ id: e.id, milestoneId: e.milestone_id, storageKey: e.storage_key, fileUrl: e.file_url, contentType: e.content_type, sizeBytes: Number(e.size_bytes), sha256: e.sha256, note: e.note, submittedAt: e.submitted_at })),
    verifications: verifications.rows.map((v) => ({ id: v.id, method: v.method, verdict: v.verdict, reason: v.reason, decidedBy: v.decided_by_id, decidedAt: v.decided_at })),
    progressPct
  };
}

async function ownedCommitment(id, userId) {
  const result = await pool.query("select * from commitments where id=$1 and user_id=$2", [id, userId]);
  return result.rows[0] || null;
}

async function programmeView(programme) {
  const rules = (await pool.query("select version,rules,effective_from from programme_rules where programme_id=$1 order by version desc limit 1", [programme.id])).rows[0];
  const commitments = (await pool.query("select * from commitments where programme_id=$1", [programme.id])).rows;
  const successful = commitments.filter((row) => row.outcome === "successful").length;
  return {
    id: programme.id, institutionId: programme.institution_id, name: programme.name, objective: programme.objective,
    startsAt: programme.starts_at, endsAt: programme.ends_at, eligibility: programme.eligibility, status: programme.status,
    visibility: programme.eligibility?.visibility || "aggregate", currentVersion: rules?.version || 1,
    rulesVersions: rules ? [{ version: rules.version, rules: rules.rules, effectiveFrom: rules.effective_from }] : [],
    results: { participants: new Set(commitments.map((row) => row.user_id)).size, commitments: commitments.length, successful, unsuccessful: commitments.filter((row) => row.outcome === "unsuccessful").length, completionRate: commitments.length ? Math.floor((successful * 100) / commitments.length) : 0 }
  };
}

async function institutionOwned(id, userId) {
  return (await pool.query("select * from institutions where id=$1 and owner_id=$2", [id, userId])).rows[0] || null;
}

const ledgerRows = async (commitmentId, client = pool) => (await client.query(
  "select id,type,amount,currency,idempotency_key,created_at from ledger_entries where commitment_id=$1 order by created_at", [commitmentId]
)).rows.map((row) => ({ id: row.id, type: row.type, amount: Number(row.amount), currency: row.currency.trim(), idempotencyKey: row.idempotency_key, createdAt: row.created_at }));

async function settlementReceipt(commitment, client = pool) {
  const ledger = await ledgerRows(commitment.id, client);
  const allocationRow = (await client.query("select * from breakage_allocations where commitment_id=$1 order by created_at desc limit 1", [commitment.id])).rows[0];
  const sum = (type) => ledger.filter((entry) => entry.type === type).reduce((total, entry) => total + entry.amount, 0);
  return {
    commitmentId: commitment.id, objective: commitment.objective, status: commitment.status, outcome: commitment.outcome,
    committed: Number(commitment.stake_amount), currency: commitment.currency.trim(),
    atRisk: Math.round((Number(commitment.stake_amount) * Number(commitment.rules?.maxForfeiturePct || 0)) / 100),
    returned: sum("return"), forfeited: sum("forfeit"), rulesVersion: commitment.rules_version, ledger,
    allocation: allocationRow ? { toSuccessPool: Number(allocationRow.to_success_pool), toPlatform: Number(allocationRow.to_platform), toInstitution: Number(allocationRow.to_institution) } : { toSuccessPool: 0, toPlatform: 0, toInstitution: 0 }
  };
}

async function saveEvidence(body, commitmentId) {
  const extension = EVIDENCE_TYPES[body.contentType];
  const encoded = String(body.dataBase64 || "");
  if (!extension) return { error: "Only JPG, PNG, WebP, and PDF files are allowed" };
  if (!encoded || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded) || encoded.length % 4 !== 0) return { error: "The uploaded file could not be read" };
  if (encoded.length > Math.ceil(MAX_EVIDENCE_BYTES * 4 / 3) + 4) return { error: "Files must be 5 MB or smaller" };
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.length > MAX_EVIDENCE_BYTES) return { error: "Files must be 5 MB or smaller" };
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const duplicate = await pool.query("select id from evidence where commitment_id=$1 and sha256=$2", [commitmentId, sha256]);
  if (duplicate.rows[0]) return { error: "This exact proof file was already uploaded" };

  await mkdir(uploadDirectory, { recursive: true });
  const storageKey = `${randomUUID()}${extension}`;
  const diskPath = resolve(uploadDirectory, storageKey);
  await writeFile(diskPath, bytes, { flag: "wx" });
  try {
    const id = randomUUID();
    const inserted = await pool.query(`insert into evidence (id,commitment_id,storage_key,file_url,content_type,size_bytes,sha256,note)
      values ($1,$2,$3,$4,$5,$6,$7,$8) returning *`, [
      id, commitmentId, storageKey, `/uploads/evidence/${storageKey}`, body.contentType, bytes.length, sha256, String(body.note || "").trim() || null
    ]);
    const evidence = inserted.rows[0];
    return { evidence: { id: evidence.id, storageKey: evidence.storage_key, fileUrl: evidence.file_url, contentType: evidence.content_type, sizeBytes: Number(evidence.size_bytes), sha256: evidence.sha256, note: evidence.note, submittedAt: evidence.submitted_at } };
  } catch (error) {
    await unlink(diskPath).catch(() => {});
    throw error;
  }
}

export async function serveEvidence(req, res, url) {
  const match = url.pathname.match(/^\/uploads\/evidence\/([0-9a-f-]+\.(?:jpg|png|webp|pdf))$/);
  if (!match) return false;
  const user = await currentUser(req);
  if (!user) { res.writeHead(401, { "content-type": "application/json" }); res.end(JSON.stringify({ error: "sign-in required" })); return true; }
  const key = match[1];
  const allowed = await pool.query(`select e.content_type from evidence e join commitments c on c.id=e.commitment_id
    where e.storage_key=$1 and c.user_id=$2`, [key, user.id]);
  if (!allowed.rows[0]) { res.writeHead(404, { "content-type": "application/json" }); res.end(JSON.stringify({ error: "evidence-not-found" })); return true; }
  try {
    const bytes = await readFile(resolve(uploadDirectory, key));
    res.writeHead(200, { "content-type": allowed.rows[0].content_type, "content-disposition": "inline" });
    res.end(bytes);
  } catch { res.writeHead(404, { "content-type": "application/json" }); res.end(JSON.stringify({ error: "evidence-not-found" })); }
  return true;
}

export async function handlePostgresApi(req, res, url, send) {
  const path = url.pathname.replace(/^\/v1/, "").split("/").filter(Boolean);
  const method = req.method;

  if (method === "POST" && path.join("/") === "auth/signup") {
    const body = await readJson(req);
    const name = String(body.name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    if (!name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return send(422, { error: "name and a valid email are required" });
    if (password.length < 10) return send(422, { error: "password must be at least 10 characters" });
    const user = { id: randomUUID(), name, email, password: passwordRecord(password) };
    try {
      const inserted = await pool.query(`insert into users (id,email,name,role,password_hash)
        values ($1,$2,$3,'user',$4::jsonb) returning *`, [user.id, user.email, user.name, JSON.stringify(user.password)]);
      const token = await issueSession(user.id);
      return send(201, { token, user: publicUser(inserted.rows[0]) });
    } catch (error) {
      if (error.code === "23505") return send(409, { error: "an account already exists for this email" });
      throw error;
    }
  }

  if (method === "POST" && path.join("/") === "auth/login") {
    const body = await readJson(req);
    const email = String(body.email || "").trim().toLowerCase();
    const result = await pool.query("select * from users where lower(email)=lower($1)", [email]);
    const user = result.rows[0];
    if (!user || !passwordMatches(String(body.password || ""), user.password_hash)) return send(401, { error: "email or password is incorrect" });
    const token = await issueSession(user.id);
    return send(200, { token, user: publicUser(user) });
  }

  const user = await currentUser(req);
  if (!user) return send(401, { error: "sign-in required" });

  if (method === "GET" && path.join("/") === "me") return send(200, { user: publicUser(user) });
  if (method === "POST" && path.join("/") === "auth/logout") {
    const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
    const digest = createHash("sha256").update(token || "").digest("hex");
    await pool.query("delete from sessions where token_digest=$1", [digest]);
    return send(200, { ok: true });
  }

  if (method === "GET" && path.length === 1 && path[0] === "commitments") {
    const rows = await pool.query("select * from commitments where user_id=$1 order by created_at desc", [user.id]);
    return send(200, await Promise.all(rows.rows.map(commitmentView)));
  }
  if (method === "GET" && path.join("/") === "dashboard/summary") {
    const rows = (await pool.query("select * from commitments where user_id=$1 and status <> 'draft'", [user.id])).rows;
    const active = rows.filter((row) => ["active", "pending_verification"].includes(row.status));
    const completed = rows.filter((row) => ["successful", "unsuccessful", "settled"].includes(row.status));
    const settledIds = rows.filter((row) => row.status === "settled").map((row) => row.id);
    const totals = settledIds.length ? (await pool.query(`select type, coalesce(sum(amount),0)::bigint as amount from ledger_entries
      where commitment_id = any($1) group by type`, [settledIds])).rows : [];
    const amount = (type) => Number(totals.find((row) => row.type === type)?.amount || 0);
    return send(200, {
      active: active.length, completed: completed.length,
      completionRate: rows.length ? Math.floor((rows.filter((row) => row.outcome === "successful").length * 100) / rows.length) : 0,
      committed: rows.reduce((sum, row) => sum + Number(row.stake_amount), 0), returned: amount("return"), forfeited: amount("forfeit"),
      notifications: Number((await pool.query("select count(*)::int as count from notifications where user_id=$1", [user.id])).rows[0].count),
      upcoming: active.sort((left, right) => new Date(left.deadline) - new Date(right.deadline)).slice(0, 5).map((row) => ({ id: row.id, objective: row.objective, deadline: row.deadline }))
    });
  }
  if (method === "GET" && path.length === 1 && path[0] === "notifications") {
    const rows = await pool.query("select id,template,payload,sent_at from notifications where user_id=$1 order by sent_at desc", [user.id]);
    return send(200, rows.rows.map((row) => ({ id: row.id, template: row.template, ...row.payload, sentAt: row.sent_at })));
  }
  if (method === "POST" && path.join("/") === "notifications/send-reminders") {
    const due = await pool.query(`select id,deadline from commitments where user_id=$1 and status='active'
      and deadline <= now() + interval '7 days'`, [user.id]);
    let sent = 0;
    for (const commitment of due.rows) {
      const exists = await pool.query(`select id from notifications where user_id=$1 and template='deadline_soon'
        and payload->>'commitmentId'=$2 and sent_at::date=current_date`, [user.id, commitment.id]);
      if (exists.rows[0]) continue;
      await pool.query("insert into notifications (id,user_id,template,payload) values ($1,$2,'deadline_soon',$3::jsonb)", [randomUUID(), user.id, JSON.stringify({ commitmentId: commitment.id, deadline: commitment.deadline })]);
      sent += 1;
    }
    return send(200, { sent });
  }
  if (method === "GET" && path.length === 1 && path[0] === "institutions") {
    const rows = await pool.query("select * from institutions where owner_id=$1 order by created_at desc", [user.id]);
    return send(200, rows.rows.map((row) => ({ id: row.id, name: row.name, ownerId: row.owner_id, status: row.status, createdAt: row.created_at })));
  }
  if (method === "POST" && path.length === 1 && path[0] === "institutions") {
    const body = await readJson(req);
    if (!String(body.name || "").trim()) return send(422, { error: "name is required" });
    const created = await pool.query("insert into institutions (id,name,owner_id,status) values ($1,$2,$3,'active') returning *", [randomUUID(), String(body.name).trim(), user.id]);
    const row = created.rows[0];
    return send(201, { id: row.id, name: row.name, ownerId: row.owner_id, status: row.status, createdAt: row.created_at });
  }
  if (method === "GET" && path.length === 1 && path[0] === "programmes") {
    const rows = await pool.query("select * from programmes order by created_at desc");
    return send(200, await Promise.all(rows.rows.map(programmeView)));
  }
  if (method === "POST" && path.length === 1 && path[0] === "programmes") {
    const body = await readJson(req);
    const institution = await institutionOwned(body.institutionId, user.id);
    const rules = body.rules || {};
    if (!institution) return send(403, { error: "you must own the institution" });
    if (!String(body.name || "").trim() || !rules.objective || !rules.startsAt || !rules.endsAt) return send(422, { error: "name and complete programme rules are required" });
    const id = randomUUID();
    const eligibility = { ...(body.eligibility || {}), visibility: "aggregate" };
    const created = await pool.query(`insert into programmes (id,institution_id,name,objective,starts_at,ends_at,eligibility,status)
      values ($1,$2,$3,$4,$5,$6,$7::jsonb,'active') returning *`, [id, institution.id, String(body.name).trim(), rules.objective, rules.startsAt, rules.endsAt, JSON.stringify(eligibility)]);
    await pool.query("insert into programme_rules (id,programme_id,version,rules,rules_hash) values ($1,$2,1,$3::jsonb,$4)", [randomUUID(), id, JSON.stringify(rules), `local-${id}-v1`]);
    return send(201, await programmeView(created.rows[0]));
  }
  if (path[0] === "programmes" && path[1]) {
    const programme = (await pool.query("select * from programmes where id=$1", [path[1]])).rows[0];
    if (!programme) return send(404, { error: "not-found" });
    if (method === "GET" && path.length === 2) return send(200, await programmeView(programme));
    if (method === "POST" && path[2] === "enrol") {
      const body = await readJson(req); const view = await programmeView(programme);
      if (programme.status !== "active") return send(409, { error: "programme is not accepting enrolments", status: programme.status });
      if (body.acceptedRulesVersion !== view.currentVersion) return send(409, { error: "rules changed; accept the current version", currentVersion: view.currentVersion });
      const id = randomUUID(); const rules = view.rulesVersions[0].rules;
      const created = await pool.query(`insert into commitments (id,user_id,programme_id,rules_version,rules,objective,deadline,stake_amount,currency,status)
        values ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9,'draft') returning *`, [id, user.id, programme.id, view.currentVersion, JSON.stringify(rules), rules.objective, rules.endsAt, rules.stake?.amount || 0, rules.stake?.currency || "NGN"]);
      return send(201, await commitmentView(created.rows[0]));
    }
  }
  if (path[0] === "users" && path[1]) {
    const target = (await pool.query("select * from users where id=$1", [path[1]])).rows[0];
    if (!target) return send(404, { error: "not-found" });
    if (method === "POST" && path[2] === "consent") {
      if (target.id !== user.id) return send(403, { error: "only your own profile can be changed" });
      const body = await readJson(req);
      const updated = await pool.query("update users set consent_profile_public=$1,updated_at=now() where id=$2 returning *", [!!body.consentProfilePublic, target.id]);
      return send(200, publicUser(updated.rows[0]));
    }
    if (method === "GET" && path[2] === "history") {
      if (target.id !== user.id && !target.consent_profile_public) return send(403, { error: "profile is private" });
      const commitments = (await pool.query("select * from commitments where user_id=$1 order by created_at desc", [target.id])).rows;
      const successful = commitments.filter((item) => item.outcome === "successful").length;
      return send(200, { user: publicUser(target), stats: { commitments: commitments.length, successful, completionRate: commitments.length ? Math.floor((successful * 100) / commitments.length) : 0 }, commitments: await Promise.all(commitments.map(commitmentView)) });
    }
  }
  if (method === "POST" && path.length === 1 && path[0] === "commitments") {
    const body = await readJson(req);
    if (!String(body.objective || "").trim() || !String(body.deadline || "").trim()) return send(422, { error: "objective and deadline are required" });
    const id = randomUUID();
    const rules = defaultRules(body);
    const result = await pool.query(`insert into commitments (id,user_id,rules,objective,deadline,stake_amount,currency,status)
      values ($1,$2,$3::jsonb,$4,$5,$6,$7,'draft') returning *`, [id, user.id, JSON.stringify(rules), String(body.objective).trim(), body.deadline, body.stakeAmount || 0, body.currency || "NGN"]);
    for (const title of (body.milestones || []).map((item) => String(item).trim()).filter(Boolean)) await pool.query("insert into milestones (id,commitment_id,title,required,done) values ($1,$2,$3,true,false)", [randomUUID(), id, title]);
    return send(201, await commitmentView(result.rows[0]));
  }

  if (path[0] !== "commitments" || !path[1]) return send(404, { error: "not-found" });
  const commitment = await ownedCommitment(path[1], user.id);
  if (!commitment) return send(404, { error: "not-found" });
  if (method === "GET" && path.length === 2) return send(200, await commitmentView(commitment));
  if (method === "GET" && path[2] === "outcome") {
    if (commitment.status !== "settled") return send(409, { error: "not settled yet", status: commitment.status });
    return send(200, await settlementReceipt(commitment));
  }

  if (method === "POST" && path[2] === "activate") {
    if (commitment.status !== "draft") return send(409, { error: "only draft can be activated", status: commitment.status });
    const updated = await pool.query("update commitments set status='active', updated_at=now() where id=$1 returning *", [commitment.id]);
    return send(200, await commitmentView(updated.rows[0]));
  }
  if (method === "POST" && path[2] === "milestones" && path.length === 3) {
    const body = await readJson(req);
    if (!String(body.title || "").trim()) return send(422, { error: "title is required" });
    const id = randomUUID();
    const created = await pool.query(`insert into milestones (id,commitment_id,title,due_at,required,done)
      values ($1,$2,$3,$4,true,false) returning *`, [id, commitment.id, String(body.title).trim(), body.dueAt || null]);
    const m = created.rows[0];
    return send(201, { id: m.id, title: m.title, dueAt: m.due_at, required: m.required, done: m.done });
  }
  if (method === "POST" && path[2] === "evidence" && path.length === 3) {
    if (commitment.status !== "active") return send(409, { error: "evidence can only be added while a commitment is active", status: commitment.status });
    const saved = await saveEvidence(await readJson(req), commitment.id);
    return saved.error ? send(422, { error: saved.error }) : send(201, saved.evidence);
  }
  if (method === "POST" && path[2] === "evidence" && path[4] === "ai-review") {
    const evidence = (await pool.query("select * from evidence where id=$1 and commitment_id=$2", [path[3], commitment.id])).rows[0];
    if (!evidence) return send(404, { error: "evidence-not-found" });
    return send(202, await queueAiAssistedReview({ evidence, commitment }));
  }
  if (method === "POST" && path[2] === "milestones" && path[4] === "toggle") {
    const body = await readJson(req);
    const updated = await pool.query(`update milestones set done=coalesce($1, not done)
      where id=$2 and commitment_id=$3 returning *`, [typeof body.done === "boolean" ? body.done : null, path[3], commitment.id]);
    if (!updated.rows[0]) return send(404, { error: "not-found" });
    const m = updated.rows[0];
    return send(200, { id: m.id, title: m.title, dueAt: m.due_at, required: m.required, done: m.done });
  }
  if (method === "POST" && path[2] === "submit-for-verification") {
    if (commitment.status !== "active") return send(409, { error: "only active can be submitted", status: commitment.status });
    const updated = await pool.query("update commitments set status='pending_verification', updated_at=now() where id=$1 returning *", [commitment.id]);
    return send(200, await commitmentView(updated.rows[0]));
  }
  if (method === "POST" && path[2] === "verify") {
    const body = await readJson(req);
    if (commitment.status !== "pending_verification") return send(409, { error: "only pending_verification can be verified", status: commitment.status });
    if (!["self_attest", "manual_review"].includes(body.method)) return send(422, { error: "method must be self_attest or manual_review" });
    if (!["successful", "unsuccessful"].includes(body.verdict)) return send(422, { error: "verdict must be successful or unsuccessful" });
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(`insert into verification_decisions (id,commitment_id,method,verdict,reason,decided_by_id)
        values ($1,$2,$3,$4,$5,$6)`, [randomUUID(), commitment.id, body.method, body.verdict, body.reason || null, user.id]);
      const updated = await client.query("update commitments set status=$1,outcome=$1,updated_at=now() where id=$2 returning *", [body.verdict, commitment.id]);
      await client.query("COMMIT");
      return send(200, await commitmentView(updated.rows[0]));
    } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
  }
  if (method === "POST" && path[2] === "settle") {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      const locked = (await client.query("select * from commitments where id=$1 and user_id=$2 for update", [commitment.id, user.id])).rows[0];
      if (locked.status === "settled") { await client.query("COMMIT"); return send(200, { settled: true, repeated: true, ...(await settlementReceipt(locked)) }); }
      if (!["successful", "unsuccessful"].includes(locked.status)) { await client.query("ROLLBACK"); return send(409, { error: "only verified commitments can settle", status: locked.status }); }
      const plan = buildSettlement(locked);
      for (const entry of plan.entries) await client.query(`insert into ledger_entries (id,commitment_id,type,amount,currency,idempotency_key)
        values ($1,$2,$3,$4,$5,$6)`, [randomUUID(), locked.id, entry.type, entry.amount, locked.currency, entry.idempotencyKey]);
      await client.query(`insert into breakage_allocations (id,commitment_id,to_success_pool,to_platform,to_institution)
        values ($1,$2,$3,$4,$5)`, [randomUUID(), locked.id, plan.allocation.toSuccessPool, plan.allocation.toPlatform, plan.allocation.toInstitution]);
      const updated = (await client.query("update commitments set status='settled', updated_at=now() where id=$1 returning *", [locked.id])).rows[0];
      await client.query("COMMIT");
      return send(200, { settled: true, repeated: false, ...(await settlementReceipt(updated)) });
    } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
  }
  return send(404, { error: "not-found" });
}

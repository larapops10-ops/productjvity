import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pool } from "./database.js";

const here = resolve(fileURLToPath(new URL(".", import.meta.url)));
const source = process.env.IMPORT_SOURCE || resolve(here, "../../../data/db.json");
const value = (item, key, fallback = null) => item?.[key] ?? fallback;
const json = (item) => JSON.stringify(item ?? {});
const timestamp = (input) => input || new Date().toISOString();

async function insert(client, statement, values) {
  await client.query(statement, values);
}

async function main() {
  const data = JSON.parse(await readFile(source, "utf8"));
  const client = await pool.connect();
  const counts = {};
  const add = (table) => { counts[table] = (counts[table] || 0) + 1; };

  try {
    await client.query("BEGIN");

    for (const user of data.users || []) {
      await insert(client, `insert into users (id,email,name,role,password_hash,consent_profile_public,created_at)
        values ($1,$2,$3,$4,$5::jsonb,$6,$7) on conflict (id) do nothing`, [
        user.id, user.email, user.name || "Member", user.role || "user",
        user.password ? json(user.password) : null, !!user.consentProfilePublic, timestamp(user.createdAt)
      ]);
      add("users");
    }

    // Older prototype records used a built-in "demo-user" without storing it in
    // the users collection. Create an inert legacy account for any such referenced
    // ID so the historical relationships remain intact. It has no password or
    // session and therefore cannot be used to sign in.
    const knownUserIds = new Set((data.users || []).map((user) => user.id));
    const referencedUserIds = new Set([
      ...(data.institutions || []).map((institution) => institution.ownerId),
      ...(data.commitments || []).map((commitment) => commitment.userId),
      ...(data.commitments || []).flatMap((commitment) => (commitment.verifications || []).map((decision) => decision.decidedBy)),
      ...(data.disputes || []).map((dispute) => dispute.reporterId),
      ...(data.notifications || []).map((notification) => notification.userId),
      ...(data.audit || []).map((audit) => audit.actorId)
    ]);
    for (const userId of referencedUserIds) {
      if (!userId || knownUserIds.has(userId)) continue;
      await insert(client, `insert into users (id,email,name,role,created_at)
        values ($1,$2,$3,'user',$4) on conflict (id) do nothing`, [
        userId, `legacy-${userId}@invalid.local`, "Legacy prototype account", new Date().toISOString()
      ]);
      add("legacy_users");
    }

    for (const session of data.sessions || []) {
      await insert(client, `insert into sessions (id,user_id,token_digest,expires_at,created_at)
        values ($1,$2,$3,$4,$5) on conflict (id) do nothing`, [
        session.id, session.userId, session.tokenDigest,
        new Date(Number(session.expiresAt) * 1000).toISOString(), timestamp(session.createdAt)
      ]);
      add("sessions");
    }

    for (const institution of data.institutions || []) {
      await insert(client, `insert into institutions (id,name,owner_id,status,created_at,updated_at)
        values ($1,$2,$3,$4,$5,$5) on conflict (id) do nothing`, [
        institution.id, institution.name, institution.ownerId, institution.status || "active", timestamp(institution.createdAt)
      ]);
      add("institutions");
    }

    for (const programme of data.programmes || []) {
      await insert(client, `insert into programmes (id,institution_id,name,objective,starts_at,ends_at,eligibility,status,created_at,updated_at)
        values ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$9) on conflict (id) do nothing`, [
        programme.id, programme.institutionId || null, programme.name, programme.objective,
        programme.startsAt, programme.endsAt, json(programme.eligibility), programme.status || "draft", timestamp(programme.createdAt)
      ]);
      add("programmes");
      for (const rule of programme.rulesVersions || []) {
        await insert(client, `insert into programme_rules (id,programme_id,version,rules,rules_hash,effective_from)
          values ($1,$2,$3,$4::jsonb,$5,$6) on conflict (programme_id,version) do nothing`, [
          `${programme.id}:rules:${rule.version}`, programme.id, rule.version, json(rule.rules),
          rule.rulesHash || `legacy-${programme.id}-${rule.version}`, timestamp(rule.effectiveFrom)
        ]);
        add("programme_rules");
      }
    }

    for (const commitment of data.commitments || []) {
      await insert(client, `insert into commitments (id,user_id,programme_id,rules_version,rules,objective,deadline,stake_amount,currency,status,outcome,created_at,updated_at)
        values ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9,$10,$11,$12,$12) on conflict (id) do nothing`, [
        commitment.id, commitment.userId, commitment.programmeId || null, commitment.rulesVersion || 1,
        json(commitment.rules), commitment.objective, commitment.deadline, commitment.stakeAmount || 0,
        commitment.currency || "NGN", commitment.status || "draft", commitment.outcome || null, timestamp(commitment.createdAt)
      ]);
      add("commitments");
      for (const milestone of commitment.milestones || []) {
        await insert(client, `insert into milestones (id,commitment_id,title,due_at,required,done)
          values ($1,$2,$3,$4,$5,$6) on conflict (id) do nothing`, [
          milestone.id, commitment.id, milestone.title, milestone.dueAt || null, milestone.required !== false, !!milestone.done
        ]);
        add("milestones");
      }
      for (const [index, evidence] of (commitment.evidence || []).entries()) {
        const evidenceId = evidence.id || `${commitment.id}:evidence:${index}`;
        const storageKey = evidence.storageKey || `legacy-${evidenceId}`;
        await insert(client, `insert into evidence (id,commitment_id,milestone_id,storage_key,file_url,content_type,size_bytes,sha256,note,submitted_at)
          values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) on conflict (id) do nothing`, [
          evidenceId, commitment.id, evidence.milestoneId || null, storageKey,
          evidence.fileUrl || `/legacy-evidence/${evidenceId}`, evidence.contentType || "application/octet-stream",
          evidence.sizeBytes || 0, evidence.sha256 || "0".repeat(64), evidence.note || evidence.fileName || null, timestamp(evidence.submittedAt)
        ]);
        add("evidence");
      }
      for (const [index, decision] of (commitment.verifications || []).entries()) {
        await insert(client, `insert into verification_decisions (id,commitment_id,method,verdict,reason,decided_by_id,decided_at)
          values ($1,$2,$3,$4,$5,$6,$7) on conflict (id) do nothing`, [
          decision.id || `${commitment.id}:decision:${index}`, commitment.id, decision.method, decision.verdict,
          decision.reason || null, decision.decidedBy || null, timestamp(decision.decidedAt)
        ]);
        add("verification_decisions");
      }
    }

    for (const [index, entry] of (data.ledger || []).entries()) {
      await insert(client, `insert into ledger_entries (id,commitment_id,type,amount,currency,idempotency_key,created_at)
        values ($1,$2,$3,$4,$5,$6,$7) on conflict (id) do nothing`, [
        entry.id || `legacy-ledger-${index}`, entry.commitmentId, entry.type, entry.amount || 0, entry.currency || "NGN",
        entry.idempotencyKey || `legacy-ledger-key-${index}`, timestamp(entry.createdAt)
      ]);
      add("ledger_entries");
    }

    for (const [index, allocation] of (data.breakage || []).entries()) {
      const split = allocation.allocation || {};
      await insert(client, `insert into breakage_allocations (id,commitment_id,to_success_pool,to_platform,to_institution,created_at)
        values ($1,$2,$3,$4,$5,$6) on conflict (id) do nothing`, [
        allocation.id || `legacy-breakage-${index}`, allocation.commitmentId, split.toSuccessPool || 0,
        split.toPlatform || 0, split.toInstitution || 0, timestamp(allocation.createdAt)
      ]);
      add("breakage_allocations");
    }

    for (const [index, dispute] of (data.disputes || []).entries()) {
      await insert(client, `insert into disputes (id,commitment_id,reporter_id,reason,status,resolution,created_at,updated_at)
        values ($1,$2,$3,$4,$5,$6,$7,$8) on conflict (id) do nothing`, [
        dispute.id || `legacy-dispute-${index}`, dispute.commitmentId, dispute.reporterId || null, dispute.reason,
        dispute.status || "open", dispute.resolution || null, timestamp(dispute.createdAt), timestamp(dispute.updatedAt || dispute.createdAt)
      ]);
      add("disputes");
    }

    for (const [index, notification] of (data.notifications || []).entries()) {
      await insert(client, `insert into notifications (id,user_id,template,payload,sent_at)
        values ($1,$2,$3,$4::jsonb,$5) on conflict (id) do nothing`, [
        notification.id || `legacy-notification-${index}`, notification.userId, notification.template,
        json(notification.payload), timestamp(notification.sentAt)
      ]);
      add("notifications");
    }

    for (const [index, audit] of (data.audit || []).entries()) {
      await insert(client, `insert into audit_logs (id,actor_id,action,target_type,target_id,diff,created_at)
        values ($1,$2,$3,$4,$5,$6::jsonb,$7) on conflict (id) do nothing`, [
        audit.id || `legacy-audit-${index}`, audit.actorId || null, audit.action, audit.targetType,
        audit.targetId, json(audit.diff), timestamp(audit.createdAt)
      ]);
      add("audit_logs");
    }

    await client.query("COMMIT");
    console.log(`Imported from ${source}`);
    for (const [table, count] of Object.entries(counts)) console.log(`${table}: ${count}`);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((error) => {
  console.error(`Import failed: ${error.message}`);
  process.exitCode = 1;
});

import { randomUUID } from "node:crypto";
import { pool } from "./database.js";

// This is deliberately a safe starting adapter. It records the request and
// routes it to a human until a provider has been deliberately configured.
export async function queueAiAssistedReview({ evidence, commitmentId }) {
  const configured = process.env.AI_REVIEW_ENABLED === "true" && process.env.AI_REVIEW_PROVIDER;
  const status = configured ? "queued" : "requires_human_review";
  const rationale = configured
    ? { nextStep: "provider worker not yet enabled" }
    : { nextStep: "manual review", reason: "AI provider is not configured" };
  const result = await pool.query(`insert into ai_review_assessments
    (id,evidence_id,commitment_id,provider,model,prompt_version,evidence_sha256,status,rationale)
    values ($1,$2,$3,$4,$5,'evidence-v1',$6,$7,$8::jsonb) returning *`, [
    randomUUID(), evidence.id, commitmentId, configured ? process.env.AI_REVIEW_PROVIDER : "not_configured",
    configured ? (process.env.AI_REVIEW_MODEL || null) : null, evidence.sha256, status, JSON.stringify(rationale)
  ]);
  const review = result.rows[0];
  return { id: review.id, status: review.status, provider: review.provider, promptVersion: review.prompt_version, rationale: review.rationale, createdAt: review.created_at };
}

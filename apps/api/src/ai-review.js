import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pool } from "./database.js";

const here = resolve(fileURLToPath(new URL(".", import.meta.url)));
const uploadDirectory = resolve(here, "../../../uploads/evidence");
const supportedImages = new Set(["image/jpeg", "image/png", "image/webp"]);
const humanOnly = { nextStep: "manual review", reason: "AI review is not configured or this file type is not eligible" };

function outputText(response) {
  for (const step of response.steps || []) {
    if (step.type !== "model_output") continue;
    const text = step.content?.find((item) => item.type === "text")?.text;
    if (text) return text;
  }
  return "";
}

function assessmentSchema() {
  return {
    type: "object",
    properties: {
      recommendation: { type: "string", enum: ["supports_completion", "does_not_support_completion", "uncertain"] },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      reasons: { type: "array", items: { type: "string" } }
    },
    required: ["recommendation", "confidence", "reasons"]
  };
}

async function requestGeminiAssessment(evidence, commitment) {
  const bytes = await readFile(resolve(uploadDirectory, evidence.storage_key));
  const prompt = [
    "You are helping a human reviewer assess task evidence.",
    `Task objective: ${commitment.objective}`,
    `Success criteria: ${commitment.rules?.successCriteria || "Not specified"}`,
    "Assess only whether the uploaded evidence appears to support completion.",
    "Do not infer private facts. If uncertain, choose uncertain.",
    "This is a recommendation only; it cannot make a final decision."
  ].join("\n");
  const response = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY, "Api-Revision": "2026-05-20" },
    body: JSON.stringify({
      model: process.env.AI_REVIEW_MODEL || "gemini-3.1-flash-lite",
      store: false,
      input: [
        { type: "text", text: prompt },
        { type: "image", data: bytes.toString("base64"), mime_type: evidence.content_type }
      ],
      response_format: { type: "text", mime_type: "application/json", schema: assessmentSchema() }
    })
  });
  if (!response.ok) {
    const details = (await response.text()).replace(/\s+/g, " ").slice(0, 400);
    throw new Error(`Gemini request failed (${response.status}): ${details}`);
  }
  const result = JSON.parse(outputText(await response.json()));
  if (!assessmentSchema().properties.recommendation.enum.includes(result.recommendation) || typeof result.confidence !== "number") throw new Error("Gemini returned an invalid assessment");
  return { recommendation: result.recommendation, confidence: Math.max(0, Math.min(1, result.confidence)), rationale: { reasons: result.reasons || [] } };
}

export async function queueAiAssistedReview({ evidence, commitment }) {
  const configured = process.env.AI_REVIEW_ENABLED === "true" && process.env.AI_REVIEW_PROVIDER === "gemini" && process.env.GEMINI_API_KEY;
  const eligible = configured && supportedImages.has(evidence.content_type);
  const created = await pool.query(`insert into ai_review_assessments
    (id,evidence_id,commitment_id,provider,model,prompt_version,evidence_sha256,status,rationale)
    values ($1,$2,$3,$4,$5,'evidence-v1',$6,$7,$8::jsonb) returning *`, [
    randomUUID(), evidence.id, commitment.id, eligible ? "gemini" : "not_configured",
    eligible ? (process.env.AI_REVIEW_MODEL || "gemini-3.1-flash-lite") : null, evidence.sha256,
    eligible ? "queued" : "requires_human_review", JSON.stringify(eligible ? { nextStep: "provider review" } : humanOnly)
  ]);
  const review = created.rows[0];
  if (!eligible) return { id: review.id, status: review.status, provider: review.provider, promptVersion: review.prompt_version, rationale: review.rationale, createdAt: review.created_at };

  try {
    const assessment = await requestGeminiAssessment(evidence, commitment);
    const status = assessment.confidence < 0.8 || assessment.recommendation === "uncertain" ? "requires_human_review" : "completed";
    const updated = await pool.query(`update ai_review_assessments set status=$1,recommendation=$2,confidence=$3,rationale=$4::jsonb,completed_at=now()
      where id=$5 returning *`, [status, assessment.recommendation, assessment.confidence, JSON.stringify(assessment.rationale), review.id]);
    return { id: review.id, status: updated.rows[0].status, provider: "gemini", recommendation: assessment.recommendation, confidence: assessment.confidence, rationale: assessment.rationale, createdAt: review.created_at };
  } catch (error) {
    const updated = await pool.query("update ai_review_assessments set status='failed',error=$1,completed_at=now() where id=$2 returning *", [error.message.slice(0, 500), review.id]);
    return { id: review.id, status: updated.rows[0].status, provider: "gemini", rationale: { nextStep: "manual review", reason: "AI request could not be completed" }, createdAt: review.created_at };
  }
}

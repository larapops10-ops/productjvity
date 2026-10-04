-- AI-assisted evidence review. Recommendations are never settlement decisions.

DO $$ BEGIN
  CREATE TYPE ai_review_status AS ENUM ('queued', 'completed', 'failed', 'requires_human_review');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS ai_review_assessments (
  id text PRIMARY KEY,
  evidence_id text NOT NULL REFERENCES evidence(id) ON DELETE CASCADE,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE CASCADE,
  provider text NOT NULL,
  model text,
  prompt_version text NOT NULL,
  evidence_sha256 char(64) NOT NULL,
  status ai_review_status NOT NULL DEFAULT 'queued',
  recommendation text CHECK (recommendation IN ('supports_completion', 'does_not_support_completion', 'uncertain')),
  confidence numeric(4,3) CHECK (confidence >= 0 AND confidence <= 1),
  rationale jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS ai_review_assessments_evidence_idx ON ai_review_assessments(evidence_id, created_at DESC);

CREATE TABLE IF NOT EXISTS accountability_partners (
  id text PRIMARY KEY,
  owner_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email text NOT NULL,
  name text,
  status text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','accepted','declined')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,email)
);

ALTER TABLE commitments ADD COLUMN IF NOT EXISTS review_mode text NOT NULL DEFAULT 'self' CHECK (review_mode IN ('self','partner','institution','platform'));
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS reviewer_partner_id text REFERENCES accountability_partners(id);

CREATE TABLE IF NOT EXISTS awards (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  commitment_id text REFERENCES commitments(id) ON DELETE CASCADE,
  milestone_id text REFERENCES milestones(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('milestone_badge','goal_badge','certificate')),
  title text NOT NULL,
  description text,
  awarded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS awards_user_idx ON awards(user_id, awarded_at DESC);

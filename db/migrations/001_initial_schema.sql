-- Productjvity initial PostgreSQL schema. Run once against the productjvity database.

DO $$ BEGIN CREATE TYPE user_role AS ENUM ('user', 'institution_admin', 'platform_admin'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE programme_status AS ENUM ('draft', 'active', 'suspended', 'closed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE commitment_status AS ENUM ('draft', 'active', 'pending_verification', 'successful', 'unsuccessful', 'settled', 'disputed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE ledger_type AS ENUM ('hold', 'return', 'forfeit', 'reward', 'fee'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE dispute_status AS ENUM ('open', 'under_review', 'resolved', 'rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS users (
  id text PRIMARY KEY,
  email text NOT NULL UNIQUE,
  name text NOT NULL,
  role user_role NOT NULL DEFAULT 'user',
  password_hash jsonb,
  consent_profile_public boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_digest text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS institutions (
  id text PRIMARY KEY,
  name text NOT NULL,
  owner_id text NOT NULL REFERENCES users(id),
  status programme_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS programmes (
  id text PRIMARY KEY,
  institution_id text REFERENCES institutions(id),
  name text NOT NULL,
  objective text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  eligibility jsonb NOT NULL DEFAULT '{}'::jsonb,
  status programme_status NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS programme_rules (
  id text PRIMARY KEY,
  programme_id text NOT NULL REFERENCES programmes(id) ON DELETE CASCADE,
  version integer NOT NULL,
  rules jsonb NOT NULL,
  rules_hash text NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  UNIQUE (programme_id, version)
);

CREATE TABLE IF NOT EXISTS commitments (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id),
  programme_id text REFERENCES programmes(id),
  rules_version integer NOT NULL DEFAULT 1,
  rules jsonb NOT NULL,
  objective text NOT NULL,
  deadline timestamptz NOT NULL,
  stake_amount bigint NOT NULL DEFAULT 0 CHECK (stake_amount >= 0),
  currency char(3) NOT NULL DEFAULT 'NGN',
  status commitment_status NOT NULL DEFAULT 'draft',
  outcome commitment_status,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS milestones (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE CASCADE,
  title text NOT NULL,
  due_at timestamptz,
  required boolean NOT NULL DEFAULT true,
  done boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS evidence (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE CASCADE,
  milestone_id text REFERENCES milestones(id) ON DELETE SET NULL,
  storage_key text NOT NULL UNIQUE,
  file_url text NOT NULL,
  content_type text NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  sha256 char(64) NOT NULL,
  note text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (commitment_id, sha256)
);

CREATE TABLE IF NOT EXISTS verification_decisions (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE CASCADE,
  method text NOT NULL,
  verdict text NOT NULL CHECK (verdict IN ('successful', 'unsuccessful')),
  reason text,
  decided_by_id text REFERENCES users(id),
  decided_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ledger_entries (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE RESTRICT,
  type ledger_type NOT NULL,
  amount bigint NOT NULL CHECK (amount >= 0),
  currency char(3) NOT NULL DEFAULT 'NGN',
  idempotency_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS breakage_allocations (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE RESTRICT,
  to_success_pool bigint NOT NULL CHECK (to_success_pool >= 0),
  to_platform bigint NOT NULL CHECK (to_platform >= 0),
  to_institution bigint NOT NULL DEFAULT 0 CHECK (to_institution >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS disputes (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE RESTRICT,
  reporter_id text REFERENCES users(id),
  reason text NOT NULL,
  status dispute_status NOT NULL DEFAULT 'open',
  resolution text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notifications (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  template text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  sent_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id text PRIMARY KEY,
  actor_id text REFERENCES users(id),
  action text NOT NULL,
  target_type text NOT NULL,
  target_id text NOT NULL,
  diff jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS commitments_user_status_idx ON commitments(user_id, status);
CREATE INDEX IF NOT EXISTS commitments_programme_idx ON commitments(programme_id);
CREATE INDEX IF NOT EXISTS evidence_commitment_idx ON evidence(commitment_id);
CREATE INDEX IF NOT EXISTS ledger_commitment_type_idx ON ledger_entries(commitment_id, type);
CREATE INDEX IF NOT EXISTS audit_target_idx ON audit_logs(target_type, target_id);

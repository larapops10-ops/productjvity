-- A Google subject is stable even if a person later changes their display name.
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_subject text;
CREATE UNIQUE INDEX IF NOT EXISTS users_google_subject_unique
  ON users(google_subject) WHERE google_subject IS NOT NULL;

-- One-time, short-lived values prevent a sign-in request from being replayed.
CREATE TABLE IF NOT EXISTS oauth_login_states (
  state text PRIMARY KEY,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS oauth_login_states_expires_idx
  ON oauth_login_states(expires_at);

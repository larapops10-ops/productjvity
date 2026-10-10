-- Test-payment records are deliberately separate from the commitment ledger.
-- A successful test charge never activates, settles, or forfeits a commitment.
CREATE TABLE IF NOT EXISTS payment_attempts (
  id text PRIMARY KEY,
  commitment_id text NOT NULL REFERENCES commitments(id) ON DELETE CASCADE,
  provider text NOT NULL,
  reference text NOT NULL UNIQUE,
  amount bigint NOT NULL CHECK (amount > 0),
  currency char(3) NOT NULL DEFAULT 'NGN',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','success','failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  verified_at timestamptz
);

CREATE INDEX IF NOT EXISTS payment_attempts_commitment_idx ON payment_attempts(commitment_id, created_at DESC);

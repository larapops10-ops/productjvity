import { pool } from "./database.js";

const tables = [
  "users", "sessions", "institutions", "programmes", "programme_rules",
  "commitments", "milestones", "evidence", "verification_decisions",
  "ledger_entries", "breakage_allocations", "disputes", "notifications", "audit_logs"
];

async function main() {
  const counts = {};
  for (const table of tables) {
    const count = await pool.query(`select count(*)::int as rows from ${table}`);
    counts[table] = count.rows[0].rows;
  }

  const checks = await pool.query(`
    select
      (select count(*) from commitments c left join users u on u.id = c.user_id where u.id is null)::int as orphaned_commitments,
      (select count(*) from evidence e left join commitments c on c.id = e.commitment_id where c.id is null)::int as orphaned_evidence,
      (select count(*) from ledger_entries l left join commitments c on c.id = l.commitment_id where c.id is null)::int as orphaned_ledger_entries`);
  const integrity = checks.rows[0];
  const healthy = Object.values(integrity).every((count) => count === 0);

  console.log("PostgreSQL import verification");
  for (const [table, count] of Object.entries(counts)) console.log(`${table}: ${count}`);
  console.log(`orphaned commitments: ${integrity.orphaned_commitments}`);
  console.log(`orphaned evidence: ${integrity.orphaned_evidence}`);
  console.log(`orphaned ledger entries: ${integrity.orphaned_ledger_entries}`);
  if (!healthy) process.exitCode = 1;
}

main()
  .catch((error) => {
    console.error(`Verification failed: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(() => pool.end());

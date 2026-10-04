import pg from "pg";

const { Pool } = pg;

const connectionString = process.env.DATABASE_URL || "postgresql://lara@localhost:5432/productjvity";

export const pool = new Pool({
  connectionString,
  max: 10,
  idleTimeoutMillis: 10_000,
  connectionTimeoutMillis: 5_000
});

export async function databaseHealth() {
  const result = await pool.query("select current_database() as database, current_user as user");
  return result.rows[0];
}

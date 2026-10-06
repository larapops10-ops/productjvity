import pg from "pg";

const { Pool } = pg;

const connectionString = process.env.DATABASE_URL || "postgresql://lara@localhost:5432/productjvity";
const isServerless = Boolean(process.env.NETLIFY || process.env.AWS_LAMBDA_FUNCTION_NAME);

export const pool = new Pool({
  connectionString,
  // Each Netlify function may be a short-lived process. Keeping this tiny
  // avoids multiplying connections when several function instances wake up.
  max: isServerless ? 1 : 10,
  idleTimeoutMillis: 10_000,
  connectionTimeoutMillis: 5_000
});

export async function databaseHealth() {
  const result = await pool.query("select current_database() as database, current_user as user");
  return result.rows[0];
}

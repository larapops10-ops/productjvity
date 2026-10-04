import { databaseHealth, pool } from "./database.js";

try {
  const status = await databaseHealth();
  console.log(`PostgreSQL connected: ${status.database} as ${status.user}`);
  await pool.end();
} catch (error) {
  console.error(`PostgreSQL connection failed: ${error.message}`);
  await pool.end();
  process.exitCode = 1;
}

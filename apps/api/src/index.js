// PostgreSQL-backed API foundation. It runs beside the existing Ruby prototype
// during migration, on port 3002 by default.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { databaseHealth } from "./database.js";
import { handlePostgresApi, serveEvidence } from "./postgres-api.js";

const PORT = Number(process.env.PORT || 3002);
const here = resolve(fileURLToPath(new URL(".", import.meta.url)));
const pagePath = resolve(here, "../../../apps/web/index.html");

function send(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "Content-Type, Authorization"
  });
  res.end(JSON.stringify(body));
}

const server = createServer(async (req, res) => {
  if (req.method === "OPTIONS") return send(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  try {
    if (await serveEvidence(req, res, url)) return;
    if (req.method === "GET" && url.pathname === "/") {
      const page = await readFile(pagePath, "utf8");
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      return res.end(page);
    }
    if (url.pathname === "/health") return send(res, 200, { ok: true, service: "productjvity-postgres-api", phase: "migration" });
    if (url.pathname === "/db-health") return send(res, 200, { ok: true, database: await databaseHealth() });
    if (url.pathname === "/openapi.json") return send(res, 200, {
      openapi: "3.0.0", info: { title: "Productjvity PostgreSQL API", version: "0.2.0" },
      paths: { "/v1/auth/signup": {}, "/v1/auth/login": {}, "/v1/me": {}, "/v1/commitments": {} }
    });
    if (url.pathname === "/v1" || url.pathname.startsWith("/v1/")) return handlePostgresApi(req, res, url, (status, body) => send(res, status, body));
    return send(res, 404, { error: "not-found" });
  } catch (error) {
    console.error(error);
    return send(res, 500, { error: "internal-server-error" });
  }
});

server.listen(PORT, () => console.log(`Productjvity PostgreSQL API listening on ${PORT}`));

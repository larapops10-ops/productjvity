// Zero-dependency API skeleton (Phase 1). No npm install needed.
// Run: PORT=3001 node apps/api/src/index.js
import { createServer } from "node:http";

const PORT = process.env.PORT || 3001;

const server = createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "productjvity-api", phase: 1 }));
    return;
  }
  if (req.url === "/openapi.json") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ openapi: "3.0.0", info: { title: "Productjvity API", version: "0.1.0" }, paths: {} }));
    return;
  }
  res.writeHead(404, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: "not-found" }));
});

server.listen(PORT, () => console.log(`api listening on ${PORT}`));

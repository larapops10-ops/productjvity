import { EventEmitter } from "node:events";
import { handlePostgresApi, serveEvidence } from "../../apps/api/src/postgres-api.js";

function requestFromEvent(event) {
  const request = new EventEmitter();
  request.method = event.httpMethod;
  request.headers = Object.fromEntries(Object.entries(event.headers || {}).map(([key, value]) => [key.toLowerCase(), value]));
  queueMicrotask(() => {
    if (event.body) request.emit("data", Buffer.from(event.body, event.isBase64Encoded ? "base64" : "utf8"));
    request.emit("end");
  });
  return request;
}

function responseCapture(resolve) {
  let statusCode = 200, headers = {}, body = Buffer.alloc(0);
  return {
    writeHead(status, nextHeaders = {}) { statusCode = status; headers = nextHeaders; },
    end(value = "") {
      body = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
      const contentType = String(headers["content-type"] || headers["Content-Type"] || "");
      resolve({ statusCode, headers, body: body.toString(contentType.startsWith("application/json") || contentType.startsWith("text/") ? "utf8" : "base64"), isBase64Encoded: !contentType.startsWith("application/json") && !contentType.startsWith("text/") });
    }
  };
}

export async function handler(event) {
  return new Promise(async (resolve, reject) => {
    const req = requestFromEvent(event);
    const res = responseCapture(resolve);
    const originalPath = new URL(event.rawUrl || `https://productjvity.netlify.app${event.path}`).pathname;
    const path = originalPath.replace(/^\/.netlify\/functions\/api/, "") || "/";
    const url = new URL(`https://productjvity.netlify.app${path}`);
    const send = (status, body) => { res.writeHead(status, { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*", "access-control-allow-methods": "GET, POST, OPTIONS", "access-control-allow-headers": "Content-Type, Authorization" }); res.end(JSON.stringify(body)); };
    try {
      if (req.method === "OPTIONS") return send(204, {});
      if (await serveEvidence(req, res, url)) return;
      if (url.pathname === "/v1" || url.pathname.startsWith("/v1/")) return handlePostgresApi(req, res, url, send);
      return send(404, { error: "not-found" });
    } catch (error) { reject(error); }
  });
}

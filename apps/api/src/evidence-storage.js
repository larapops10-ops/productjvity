import { createHash, createHmac } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
// `import.meta.url` is not retained when Netlify bundles this module as a
// serverless function. The project working directory works for local use and
// avoids making the function fail before it can reach R2.
const localDirectory = resolve(process.cwd(), "uploads/evidence");
const r2Configured = () => Boolean(process.env.R2_ACCOUNT_ID && process.env.R2_ACCESS_KEY_ID && process.env.R2_SECRET_ACCESS_KEY && process.env.R2_BUCKET);
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const hmac = (key, value, encoding) => createHmac("sha256", key).update(value).digest(encoding);
const r2Endpoint = () => process.env.R2_ENDPOINT || `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
const encodedKey = (key) => key.split("/").map(encodeURIComponent).join("/");

function r2Request(key, method, bytes) {
  const endpoint = new URL(r2Endpoint());
  const now = new Date();
  const timestamp = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const date = timestamp.slice(0, 8);
  const payloadHash = sha256(bytes || "");
  const canonicalUri = `/${encodeURIComponent(process.env.R2_BUCKET)}/${encodedKey(key)}`;
  const canonicalHeaders = `host:${endpoint.host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${timestamp}\n`;
  const signedHeaders = "host;x-amz-content-sha256;x-amz-date";
  const canonicalRequest = [method, canonicalUri, "", canonicalHeaders, signedHeaders, payloadHash].join("\n");
  const scope = `${date}/auto/s3/aws4_request`;
  const stringToSign = ["AWS4-HMAC-SHA256", timestamp, scope, sha256(canonicalRequest)].join("\n");
  const dateKey = hmac(`AWS4${process.env.R2_SECRET_ACCESS_KEY}`, date);
  const regionKey = hmac(dateKey, "auto");
  const serviceKey = hmac(regionKey, "s3");
  const signingKey = hmac(serviceKey, "aws4_request");
  const signature = hmac(signingKey, stringToSign, "hex");
  return { url: `${endpoint.origin}${canonicalUri}`, headers: {
    host: endpoint.host, "x-amz-content-sha256": payloadHash, "x-amz-date": timestamp,
    authorization: `AWS4-HMAC-SHA256 Credential=${process.env.R2_ACCESS_KEY_ID}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`
  } };
}

export async function putEvidenceObject(key, bytes, contentType) {
  if (!r2Configured()) { await mkdir(localDirectory, { recursive: true }); await writeFile(resolve(localDirectory, key), bytes, { flag: "wx" }); return; }
  const signed = r2Request(key, "PUT", bytes);
  const response = await fetch(signed.url, { method: "PUT", headers: { ...signed.headers, "content-type": contentType }, body: bytes });
  if (!response.ok) throw new Error(`R2 upload failed (${response.status})`);
}

export async function getEvidenceObject(key) {
  if (!r2Configured()) return readFile(resolve(localDirectory, key));
  const signed = r2Request(key, "GET");
  const response = await fetch(signed.url, { headers: signed.headers });
  if (!response.ok) throw new Error(`R2 download failed (${response.status})`);
  return Buffer.from(await response.arrayBuffer());
}

export async function deleteEvidenceObject(key) {
  if (!r2Configured()) { await unlink(resolve(localDirectory, key)).catch(() => {}); return; }
  const signed = r2Request(key, "DELETE");
  await fetch(signed.url, { method: "DELETE", headers: signed.headers }).catch(() => {});
}

export const evidenceStorageMode = () => r2Configured() ? "r2" : "local";

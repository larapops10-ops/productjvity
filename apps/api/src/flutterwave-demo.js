import { randomUUID } from "node:crypto";
import { pool } from "./database.js";

const configured = () => Boolean(process.env.FLUTTERWAVE_SECRET_KEY);

async function flutterwave(path, options = {}) {
  const response = await fetch(`https://api.flutterwave.com/v3${path}`, {
    ...options,
    headers: { authorization: `Bearer ${process.env.FLUTTERWAVE_SECRET_KEY}`, "content-type": "application/json", ...(options.headers || {}) }
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.status !== "success") throw new Error(body.message || "Flutterwave could not complete the test payment");
  return body.data;
}

export async function startTestPayment({ commitment, user, origin }) {
  if (!configured()) throw new Error("Test payments are not set up yet");
  if (Number(commitment.stake_amount) <= 0) throw new Error("Add a test amount to this goal first");
  const reference = `pj_test_${randomUUID().replaceAll("-", "")}`;
  const amount = (Number(commitment.stake_amount) / 100).toFixed(2);
  const data = await flutterwave("/payments", { method: "POST", body: JSON.stringify({
    tx_ref: reference, amount, currency: commitment.currency.trim(), redirect_url: `${origin}/v1/payments/flutterwave/callback`,
    customer: { email: user.email, name: user.name }, customizations: { title: "Productjvity test payment", description: "Demo only — no real commitment money is collected." }, meta: [{ metaname: "test_mode", metavalue: "true" }]
  }) });
  await pool.query(`insert into payment_attempts (id,commitment_id,provider,reference,amount,currency)
    values ($1,$2,'flutterwave_test',$3,$4,$5)`, [randomUUID(), commitment.id, reference, commitment.stake_amount, commitment.currency]);
  return { authorizationUrl: data.link, reference };
}

export async function confirmTestPayment(reference, transactionId) {
  const attempt = (await pool.query("select * from payment_attempts where reference=$1", [reference])).rows[0];
  if (!attempt) throw new Error("Payment attempt was not found");
  if (!configured() || !transactionId) throw new Error("Test payments are not set up yet");
  const data = await flutterwave(`/transactions/${encodeURIComponent(transactionId)}/verify`);
  const expectedAmount = Number(attempt.amount) / 100;
  const success = data.status === "successful" && data.tx_ref === reference && Number(data.amount) === expectedAmount && data.currency === attempt.currency.trim();
  await pool.query("update payment_attempts set status=$1,verified_at=now() where reference=$2", [success ? "success" : "failed", reference]);
  return success;
}

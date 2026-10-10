import { randomUUID } from "node:crypto";
import { pool } from "./database.js";

const configured = () => Boolean(process.env.PAYSTACK_SECRET_KEY);

async function paystack(path, options = {}) {
  const response = await fetch(`https://api.paystack.co${path}`, {
    ...options,
    headers: { authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}`, ...(options.headers || {}) }
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.status) throw new Error(body.message || "Paystack could not complete the test payment");
  return body.data;
}

export async function startTestPayment({ commitment, user, origin }) {
  if (!configured()) throw new Error("Test payments are not set up yet");
  if (Number(commitment.stake_amount) <= 0) throw new Error("Add a test amount to this goal first");
  const reference = `pj_test_${randomUUID().replaceAll("-", "")}`;
  const payload = new URLSearchParams({
    email: user.email,
    amount: String(Number(commitment.stake_amount)),
    currency: commitment.currency.trim(),
    reference,
    callback_url: `${origin}/v1/payments/paystack/callback`,
    metadata: JSON.stringify({ product: "Productjvity test payment", commitmentId: commitment.id, testMode: true })
  });
  const data = await paystack("/transaction/initialize", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: payload });
  await pool.query(`insert into payment_attempts (id,commitment_id,provider,reference,amount,currency)
    values ($1,$2,'paystack_test',$3,$4,$5)`, [randomUUID(), commitment.id, reference, commitment.stake_amount, commitment.currency]);
  return { authorizationUrl: data.authorization_url, reference };
}

export async function confirmTestPayment(reference) {
  const attempt = (await pool.query("select * from payment_attempts where reference=$1", [reference])).rows[0];
  if (!attempt) throw new Error("Payment attempt was not found");
  if (!configured()) throw new Error("Test payments are not set up yet");
  const data = await paystack(`/transaction/verify/${encodeURIComponent(reference)}`);
  const success = data.status === "success" && Number(data.amount) === Number(attempt.amount) && data.currency === attempt.currency.trim();
  await pool.query("update payment_attempts set status=$1,verified_at=now() where reference=$2", [success ? "success" : "failed", reference]);
  return success;
}

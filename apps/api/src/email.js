const ZEPTOMAIL_ENDPOINT = "https://api.zeptomail.com/v1.1/email";

function escapeHtml(value) {
  return String(value || "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]));
}

function sender() {
  const raw = String(process.env.ZEPTO_FROM || "").trim();
  const match = raw.match(/^(.*?)\s*<([^>]+)>$/);
  return match ? { name: match[1].trim() || "Productjvity", address: match[2].trim() } : { name: "Productjvity", address: raw };
}

export function emailIsConfigured() {
  return Boolean(process.env.ZEPTO_API_KEY && sender().address);
}

// This deliberately fails safely: an in-app invitation remains available even
// when email has not been connected yet.
export async function sendPartnerInvitation({ ownerName, recipientName, recipientEmail }) {
  if (!emailIsConfigured()) return { sent: false, reason: "email_not_configured" };
  const from = sender();
  const greeting = recipientName ? `Hello ${escapeHtml(recipientName)},` : "Hello,";
  const owner = escapeHtml(ownerName || "A Productjvity member");
  const htmlbody = `<p>${greeting}</p><p><strong>${owner}</strong> has asked you to be their accountability partner on Productjvity.</p><p>Sign in using <strong>${escapeHtml(recipientEmail)}</strong> to accept the invitation and review proof when they are ready.</p><p>Thank you for helping someone follow through.</p>`;
  try {
    const response = await fetch(ZEPTOMAIL_ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Zoho-enczapikey ${process.env.ZEPTO_API_KEY}` },
      body: JSON.stringify({
        from,
        to: [{ email_address: { address: recipientEmail, name: recipientName || recipientEmail } }],
        subject: `${ownerName || "A friend"} invited you to Productjvity`,
        htmlbody
      })
    });
    if (!response.ok) return { sent: false, reason: "provider_rejected" };
    return { sent: true };
  } catch { return { sent: false, reason: "provider_unavailable" }; }
}

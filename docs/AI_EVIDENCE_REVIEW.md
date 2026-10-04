# AI-assisted evidence review

Productjvity may ask an AI service to examine an uploaded proof file and provide a recommendation for a human reviewer. This is off by default.

## Safety rules

- An AI recommendation never activates, verifies, settles, forfeits, or pays a commitment.
- A person must make every verification that affects money or a member's record.
- The assessment stores the provider, model, prompt version, evidence fingerprint, confidence, rationale, errors, and timestamps for audit.
- Low-confidence or uncertain results must go to manual review.
- The provider receives only the evidence and the minimum task criteria necessary for that review.
- Use clear member consent and a privacy notice before enabling an external AI provider.

## Enabling later

Set `AI_REVIEW_ENABLED=true`, choose a provider and model, and supply that provider's secret through the deployment environment. Do not put an API key in the app, browser code, Git, or this file.

Until a provider is explicitly configured, review requests are recorded as `requires_human_review`; no evidence leaves Productjvity.

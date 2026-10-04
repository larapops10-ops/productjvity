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

To enable the Gemini pilot, set `AI_REVIEW_ENABLED=true`, `AI_REVIEW_PROVIDER=gemini`, and add `GEMINI_API_KEY` through the deployment environment. Do not put an API key in the app, browser code, Git, or this file. The pilot sends only JPG, PNG, and WebP proof files plus the task objective and success criteria. PDFs continue to manual review.

Until a provider is explicitly configured, review requests are recorded as `requires_human_review`; no evidence leaves Productjvity. Gemini requests use `store: false`, but a free-tier account may still use submitted content to improve Google's products. Use sample proofs only until you move to a paid privacy-appropriate arrangement.

## Save a local key safely

From the project folder, run `sh scripts/configure-gemini.sh`. It hides the key while you paste it and saves it only in the ignored `.env` file. Restart the PostgreSQL API afterwards.

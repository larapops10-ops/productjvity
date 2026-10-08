# Productjvity online deployment

This keeps the original architecture: hosted PostgreSQL for app data, private Cloudflare R2 for proof files, and Netlify for the public site plus API function.

## What is already prepared

- `netlify/functions/api.mjs` runs the existing API as a Netlify Function.
- `apps/api/src/evidence-storage.js` uses Cloudflare R2 when the R2 settings exist, while retaining local file storage for development.
- `netlify.toml` contains the production routing rules. `netlify.demo.toml` preserves the optional visual-only demo configuration.

## One-time account setup still required

1. Create a hosted PostgreSQL database and copy its connection string.
2. Create a private Cloudflare R2 bucket and make an R2 API token with read/write access limited to that bucket.
3. In Netlify, save these environment variables: `DATABASE_URL`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, and `R2_ENDPOINT`.
4. Use the pooled Neon connection (its host contains `-pooler`) and run `scripts/migrate-hosted-postgres.sh` to apply `001_initial_schema.sql`, `002_ai_review_assessments.sql`, and `003_accountability_and_awards.sql`. This creates an empty production database; do not copy development accounts or uploaded proof into a public app.
5. Deploy from the repository, then test sign-up, a proof upload, and partner review.

## Google sign-in

1. In Google Cloud, create a **Web application** OAuth client and authorize `https://productjvity.netlify.app/v1/auth/google/callback` as its redirect URI.
2. Save `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, and `GOOGLE_OAUTH_REDIRECT_URI=https://productjvity.netlify.app/v1/auth/google/callback` as secret Netlify variables for Production.
3. Apply migration `004_google_sign_in.sql`, then redeploy. While the Google app is in Testing, add each tester's Google email under Google Auth Platform → Audience → Test users.
4. Before changing Google to Production, publish a clear privacy policy and terms page and keep requested Google permissions limited to `openid`, `email`, and `profile`.

## Security rules

- Keep the R2 bucket private. Proof is read only through the authenticated API.
- Never paste the database URL, R2 secret, Gemini key, or email token into GitHub or chat.
- Start with no real payments. Add a regulated payment provider only after the public beta has been tested.

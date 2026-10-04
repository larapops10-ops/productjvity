# Sending accountability invitations by email

Productjvity already keeps every invitation inside the app. Email is an optional extra: it lets a partner know that they have been invited without needing to check the app first.

## What you need

Create a ZeptoMail account, verify a sender email or domain, and copy its **Send Mail token**. Keep that token private; never put it in GitHub or paste it into chat.

## One-time local setup

From the Productjvity project folder, run:

```sh
sh scripts/configure-zeptomail.sh
```

The helper asks for the sender email, display name, and token. It saves them only in the local `.env` file, which is excluded from GitHub.

Restart the local app afterwards. From then on, every new accountability-partner invitation is emailed as well as appearing inside Productjvity.

If ZeptoMail is not configured or is temporarily unavailable, invitations still work inside the app and no goal is automatically failed.

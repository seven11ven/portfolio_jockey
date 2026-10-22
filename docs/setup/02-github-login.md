# Setup 2: GitHub login

Portfolio Jockey has no passwords. You sign in with GitHub, and only the emails you list in `ALLOWED_EMAILS` are let in.

**You'll need:** about 10 minutes, and Setup 1 (Neon) finished.

## 1. Find the address you'll open the app at
GitHub only sends people back to the exact address you register, so decide this first.
- **On your own computer**, or **VS Code desktop connected to a Codespace:** `http://localhost:3000`
- **Codespaces in a web browser:** start the app once with `npm run dev`. In the **Ports** tab, open port 3000 in the browser and copy the address. It looks like `https://<codespace-name>-3000.app.github.dev`. Stop the app with `Ctrl+C` afterward. Keep the port's visibility **Private**.

This guide calls that address `APP_URL`.

## 2. Create a GitHub OAuth App
1. Go to **github.com > Settings > Developer settings > OAuth Apps > New OAuth App**.
2. Fill it in:
   - **Application name:** `Portfolio Jockey (dev)`
   - **Homepage URL:** `APP_URL`
   - **Authorization callback URL:** `APP_URL/api/auth/callback/github`
3. Click **Register application**.
4. Copy the **Client ID**.
5. Click **Generate a new client secret** and copy it right away. GitHub shows it only once.

> Later, for the live site on Vercel, you'll create a **second** OAuth App with the Vercel address. Each OAuth App allows only one callback URL.

## 3. Add the values to `.env`
Open `.env` in the repo root and fill in these lines. Never paste them into code, chats or `.env_example`.
```
BETTER_AUTH_URL=APP_URL
GITHUB_CLIENT_ID=your client id
GITHUB_CLIENT_SECRET=your client secret
ALLOWED_EMAILS=the primary email on your GitHub account
```
`ALLOWED_EMAILS` can hold several emails separated by commas. Use the **primary** email from **github.com > Settings > Emails**. It must be verified.

## 4. Generate the login secret
This writes a random secret into `.env` without printing it. Run it from the repo root:
```
grep -q '^BETTER_AUTH_SECRET=' .env || echo 'BETTER_AUTH_SECRET=' >> .env
sed -i "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=$(openssl rand -hex 32)|" .env
```

## 5. Try it
1. Run `npm run dev` and open `APP_URL`. You should land on the login page.
2. Click **Continue with GitHub** and approve. You should see "Signed in as" with your name.
3. Click **Sign out**. You should be back on the login page.
4. Stop the app with `Ctrl+C`, so port 3000 doesn't stay open.

## Troubleshooting
- **"This GitHub account isn't approved":** the email in `ALLOWED_EMAILS` doesn't match your GitHub primary email, or that email isn't verified.
- **GitHub says the redirect URI isn't associated with this application:** `BETTER_AUTH_URL` and the OAuth App's callback URL don't match exactly. Check `http` versus `https`, the port, and trailing slashes.
- **The app won't start and lists invalid environment variables:** fix the variables it names. The error names them but never prints their values.

## If a secret ever leaks
- **GitHub client secret:** in the OAuth App settings, generate a new secret, delete the old one, and update `.env`.
- **`BETTER_AUTH_SECRET`:** run the command in step 4 again. Everyone is signed out.

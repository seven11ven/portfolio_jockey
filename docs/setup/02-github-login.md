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
   - **Authorization callback URL:** `APP_URL/api/auth/callback/github`. GitHub may label this field **Redirect URL**. It's the same field.
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
**Codespaces in a web browser only:** also add this line. Codespaces' proxy rewrites each request's origin to `https://localhost:3000`, and without it, signing out fails with "Invalid origin":
```
TRUSTED_ORIGINS=https://localhost:3000
```
Leave `TRUSTED_ORIGINS` empty everywhere else, including Vercel.

`ALLOWED_EMAILS` can hold several emails separated by commas. Use the **primary** email from **github.com > Settings > Emails**. It must be verified.

## 4. Generate the login secret
This writes a random secret into `.env` without printing it.

1. If `.env` is open in your editor, close it first. Otherwise saving the editor's copy later would erase the secret.
2. Run these commands. The first line moves you to the repo root from any folder, so the secret lands in the right `.env`:
   ```
   cd "$(git rev-parse --show-toplevel)"
   grep -q '^BETTER_AUTH_SECRET=' .env || printf '\nBETTER_AUTH_SECRET=\n' >> .env
   sed -i "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=$(openssl rand -hex 32)|" .env
   ```
3. Check it worked without showing the secret. This should print `64`:
   ```
   grep '^BETTER_AUTH_SECRET=' .env | cut -d= -f2 | tr -d '\n' | wc -c
   ```

## 5. Try it
1. Run `npm run dev` and open `APP_URL`. You should land on the login page.
2. Click **Continue with GitHub** and approve. You should see "Signed in as" with your name.
3. Click **Sign out**. You should be back on the login page.
4. Stop the app with `Ctrl+C`, so port 3000 doesn't stay open.

## Troubleshooting
- **"This GitHub account isn't approved":** the email in `ALLOWED_EMAILS` doesn't match your GitHub primary email, or that email isn't verified.
- **The secret check prints `0`, or the app says `BETTER_AUTH_SECRET` is required:** the commands probably ran in a different folder and created a second `.env` there. Delete that stray `.env`, then rerun step 4. The first command now moves you to the repo root.
- **Sign out bounces back to the signed-in page, or says "Sign-out didn't work":** the dev server log shows `Invalid origin`. In Codespaces, set `TRUSTED_ORIGINS=https://localhost:3000` as described in step 3.
- **GitHub says the redirect URI isn't associated with this application:** `BETTER_AUTH_URL` and the OAuth App's callback URL don't match exactly. Check `http` versus `https`, the port, and trailing slashes.
- **The app won't start and lists invalid environment variables:** fix the variables it names. The error names them but never prints their values.

## If a secret ever leaks
- **GitHub client secret:** in the OAuth App settings, generate a new secret, delete the old one, and update `.env`.
- **`BETTER_AUTH_SECRET`:** run the command in step 4 again. Everyone is signed out.

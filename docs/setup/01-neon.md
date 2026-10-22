# Setup 1: Neon database

Portfolio Jockey stores projects, notes and file records in a free Neon Postgres database. Uploaded files themselves go to Cloudflare R2, which is covered in a later guide.

**You'll need:** about 10 minutes and a GitHub account.

## 1. Create a Neon project
1. Go to [neon.tech](https://neon.tech) and sign up. Signing in with GitHub works.
2. Create a new project.
   - **Name:** anything, such as `portfolio-jockey`.
   - **Postgres version:** keep the default.
   - **Region:** pick **AWS US East (N. Virginia)**. Vercel runs its functions in that area by default, so a nearby database keeps the app fast. If you deploy elsewhere, choose the region closest to your Vercel functions.
3. Stay on the **Free** plan. Don't add a payment method.

## 2. Copy the connection string
1. On the project dashboard, click **Connect**.
2. Turn **Connection pooling** on.
3. Copy the connection string. It starts with `postgresql://`.

> **This string contains your database password.** Treat it like a password. Never paste it into code, an issue, a chat, or `.env_example`.

## 3. Add it to your `.env` file
1. In the repo root, open `.env`. If it doesn't exist, copy `.env_example` to a new file named `.env`.
2. Set the value:
   ```
   DATABASE_URL=postgresql://...your string...
   ```
3. Check that Git ignores it. This should print `.env`:
   ```
   git check-ignore .env
   ```

## 4. Create the tables
Run the migrations. They create every table the app needs.
```
npm run db:migrate
```
In the Neon console, open **Tables**. You should see `user`, `session`, `account`, `verification`, `projects`, `entries` and `files`.

## If the string ever leaks
In the Neon console, go to **Roles**, reset the password for your role, and update `.env` and Vercel with the new connection string. The old one stops working right away.

## Notes
- `npm run db:studio` opens a local database browser on a port. Stop it with `Ctrl+C` when you're done, so the port doesn't stay open.
- When the schema in `src/db/schema.ts` changes, run `npm run db:generate` to create a new migration, then `npm run db:migrate` to apply it.

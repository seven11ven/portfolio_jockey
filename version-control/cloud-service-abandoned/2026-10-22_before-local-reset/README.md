# Backup: before resetting to a fully local app

Snapshot taken on 2026-10-22. The project manager decided Portfolio Jockey
will be a fully local app, so GitHub login, Neon Postgres and Vercel Blob
storage are no longer needed. Every dependency and all app code was removed
so a new plan can choose the stack from scratch.

This is the last cloud version (commit `d6f8220`):

- `src/`: Next.js 16 app. Better Auth GitHub login with an email allowlist,
  Neon database client and schema, Vercel Blob storage, the free-allowance
  guard, and the upload, permission, complete and file API routes.
- `drizzle/`: migrations 0000 to 0003 and their snapshots.
- `public/`: default Next.js icons.
- `package.json`, `package-lock.json`: every dependency before removal.
- `next.config.ts`, `tsconfig.json`, `eslint.config.mjs`, `drizzle.config.ts`.
- `.env_example`: the database, auth, storage and limits variables.
- `.devcontainer/devcontainer.json`: ran `npm ci` and forwarded port 3000.

The setup guides from `docs/setup/` are documentation, so they aren't copied
here. They're in Git history at commit `d6f8220`.

## Restore
Copy the files back to the repo root, keeping their paths, then run `npm ci`.
The app needs a filled-in `.env`, a Neon database, a GitHub OAuth App and a
private Vercel Blob store. Those cloud resources may have been deleted.

No secrets are included.

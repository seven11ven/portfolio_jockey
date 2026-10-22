# Database setup (plan step 3)

**Date:** 2026-10-22
**Time:** 2026-10-22 01:45 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Change
- **Schema:** added `src/db/schema.ts` with Drizzle ORM.
  - Login tables for Better Auth: `user`, `session`, `account`, `verification`. Fields match what Better Auth 1.7 requires, checked against its bundled table definitions.
  - App tables: `projects`, `entries`, `files`.
    - `projects.last_opened_at` drives the dashboard's "most recently opened" order, with a matching index.
    - `entries` holds a note, attached files, or both. This replaces the separate "note or file" type from the plan, because the approved mockups show captions on media.
    - `files` stores metadata only. File contents live in the private R2 bucket. A `pending` or `ready` status lets in-flight uploads count toward the storage quota.
  - Every app row stores its owner's `user_id`. Deleting a user, project or entry cascades to the rows that belong to it.
- **Migration:** generated `drizzle/0000_init.sql` with `drizzle-kit`. It contains table definitions only, no data.
- **Database client:** added `src/db/index.ts`, using Neon's HTTP driver. Better Auth's Drizzle adapter only needs transactions on MySQL, so this driver works with it on Postgres.
- **Environment check:** added `src/lib/env.ts`. It validates environment variables with zod and fails with a clear message naming the problem variable. It never prints values. Only `DATABASE_URL` is required for now.
- **Server-only guard:** installed `server-only`. Database and environment code import it, so the build fails if browser code ever imports them.
- **Config and scripts:** added `drizzle.config.ts`, which loads `.env` with Node's built-in loader. Added the `db:generate`, `db:migrate` and `db:studio` scripts.
- **Setup guide:** added `docs/setup/01-neon.md` with step-by-step Neon instructions for the owner and for learners.

## Version control
- Backed up `package.json` and `package-lock.json` to `version-control/2026-10-22_before-database/` before changing dependencies.

## Verification
- Applied the migration to a temporary in-memory Postgres (PGlite, outside the repo):
  - All statements ran.
  - Deleting a project removed its entries and file records.
  - Duplicate R2 keys were rejected.
  - File sizes summed correctly for the quota.
- `npm run lint`, `npm run typecheck` and `npm run build` pass.
- `npm audit`: unchanged. Only the known `braces` issue in the ESLint toolchain remains, with no fix available.

## Impacts
- The owner must create a Neon project, set `DATABASE_URL` in `.env`, and run `npm run db:migrate`. See `docs/setup/01-neon.md`.
- No page uses the database yet, so the app still builds without `.env`.

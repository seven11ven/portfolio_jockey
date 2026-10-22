# File storage switched from Cloudflare R2 to Backblaze B2

**Date:** 2026-10-22
**Time:** 2026-10-22 06:03 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Why
Cloudflare required a payment card before an R2 bucket could be created. The project has a zero budget, and the project manager doesn't want a card on file. Backblaze B2's sign-up page says no credit card is required, and it offers 10 GB of free storage through an S3-compatible API, so the existing storage code carries over.

## Change
- **Provider-neutral settings:** the `R2_*` variables were replaced with `STORAGE_ENDPOINT`, `STORAGE_REGION`, `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY` and `STORAGE_BUCKET`, in `src/lib/env.ts` and `.env_example`. `R2_ACCOUNT_ID` and `R2_ENDPOINT` were removed. The endpoint now always comes from `STORAGE_ENDPOINT`.
- **Storage client:** `src/lib/r2.ts` was renamed to `src/lib/object-storage.ts`. It now uses the configured endpoint and region. Upload and download behavior is unchanged: size and type are locked into upload links, checksum fields are only added when required, and URLs are path-style.
- **Database:** the `r2_key` columns in `files` and `deleted_objects` were renamed to `storage_key` in migration `drizzle/0002_rename_storage_key.sql`, and the unique constraint was renamed to match. The migration was applied to Neon, which now has 3 migrations.
  - `drizzle-kit` needs an interactive terminal to confirm renames. It was run through a pseudo-terminal, with "rename column" chosen for both tables. The generated SQL contains only renames and a constraint swap, with no drops of data.
- **Storage logic and routes:** `src/lib/storage.ts` and the upload-complete route now use the new names. Comments say "bucket" or "storage" instead of R2.
- **Docs:** removed `docs/setup/03-cloudflare-r2.md` and added `docs/setup/03-backblaze-b2.md`. It covers:
  - A private, encrypted bucket.
  - The "Keep only the last version" lifecycle setting, so hidden (deleted) files are erased about a day after the app deletes them.
  - An application key limited to the one bucket, with read and write access.
  - **/bin/bash spending caps**, so B2 stops a chargeable action instead of billing.
  - The CORS rule, set once with the `b2` command-line tool (version 5). The commands were checked against the tool's own help. The tool runs in a temporary folder and is signed out and removed afterwards.
  - How to recover a deleted file within 7 days.
- `docs/setup/01-neon.md`: now refers to Backblaze B2 instead of R2.
- **Build fix:** `tsconfig.json` and `eslint.config.mjs` now exclude `version-control/`. The old R2 backup files were being type-checked and broke the build. Backups are reference copies and shouldn't be compiled or linted.

## Version control
- Backed up `src/lib/r2.ts`, `src/lib/env.ts`, `src/lib/storage.ts`, `src/db/schema.ts`, the upload-complete route, `.env_example`, `tsconfig.json` and `eslint.config.mjs` to `version-control/2026-10-22_before-backblaze/`. The backup includes restore notes for the column rename. No secrets were backed up.

## Verification
- Migrations 0000, 0001 and 0002 were run in an in-memory Postgres (PGlite) with data inserted before the rename. The data survived, and duplicate keys were still rejected.
- `npx tsc --noEmit`, `npx eslint` and `npm run build` pass.
- **Storage logic test, 30 of 30 passed:** run against real Neon with throwaway test users, and Moto (a local S3 simulator) standing in for the bucket. It covers:
  - Type, size, ownership and id rules.
  - Upload links signing only content-length, content-type and host, with no checksum fields.
  - A browser-style upload.
  - Owner-only completion and downloads.
  - Mismatch cleanup.
  - 5 parallel uploads against a 100-byte quota: exactly 2 allowed.
  - Retention, purge, abandoned uploads and project delete.
- All test rows were removed from Neon, with 0 left. Moto (port 5055) was stopped, and the port was confirmed closed.

## Still to verify on the real Backblaze bucket
- Presigned uploads with the signed size and type, and B2 rejecting a wrong size.
- The download `Content-Disposition` header. Moto ignores response overrides.
- The CORS rule's `s3_put`, `s3_get` and `s3_head` operation names. These come from community reports, not Backblaze's own documentation.
- Multi-object delete, and hidden files being erased under "Keep only the last version".

## Impacts
- The app needs the five `STORAGE_*` values in `.env` to start. See `docs/setup/03-backblaze-b2.md`.
- There's no longer any Cloudflare dependency.

---

# Backblaze B2 abandoned

**Time:** 2026-10-22 06:14 UTC

When the project manager tried to sign up, Backblaze B2 asked for a form of payment, and its pricing page presents B2 as a pay-as-you-go service. That conflicts with the Budgeting guideline. The "no credit card required" claim had come from search-result summaries, not from checking the provider's site directly. None of the Backblaze changes were committed. File storage moved to Vercel Blob instead. See `vercel-blob-switch.md`.

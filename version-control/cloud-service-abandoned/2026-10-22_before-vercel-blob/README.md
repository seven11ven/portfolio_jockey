# Backup: before switching file storage to Vercel Blob

Snapshot taken on 2026-10-22. Backblaze B2 turned out to require payment
details, so the project manager chose Vercel Blob (free on the Hobby plan,
no card, and it blocks instead of billing at its limits).

These are the S3-compatible (Backblaze B2) versions. They were never
committed, so this folder is the only copy:

- `package.json`, `package-lock.json`: before `@vercel/blob@2.8.0` was added and
  the `@aws-sdk/*` packages were removed.
- `src/lib/object-storage.ts`: the S3 client (`STORAGE_*` settings).
- `src/lib/env.ts`: `STORAGE_ENDPOINT`, `STORAGE_REGION`, `STORAGE_ACCESS_KEY_ID`,
  `STORAGE_SECRET_ACCESS_KEY`, `STORAGE_BUCKET`.
- `src/lib/storage.ts`: upload, download and delete logic for S3.
- `src/db/schema.ts`: before the `blob_usage_events` table.
- `src/app/api/uploads/route.ts`: returned an S3 upload URL.
- `.env_example`: Backblaze B2 section.

No secrets are included.

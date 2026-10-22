# Backup: before switching file storage from Cloudflare R2 to Backblaze B2

Snapshot taken on 2026-10-22, matching commit `22d79c6`
("Add private R2 storage and sync agent files with secrets backup rule").

Cloudflare required a payment card before creating an R2 bucket, so the
project manager chose Backblaze B2, which doesn't. These are the R2-specific
versions of the changed files:

- `src/lib/r2.ts`: the R2 client (replaced by `src/lib/object-storage.ts`).
- `src/lib/env.ts`: `R2_*` settings.
- `src/lib/storage.ts`: imported from `r2.ts` and used `r2Key`.
- `src/db/schema.ts`: `r2_key` columns (renamed to `storage_key` in migration `0002`).
- `src/app/api/uploads/[fileId]/complete/route.ts`: comment mentioning R2.
- `.env_example`: R2 section.

To restore, copy the files back and add a migration that renames
`storage_key` back to `r2_key` in `files` and `deleted_objects`.
- `tsconfig.json` and `eslint.config.mjs`: before `version-control/` was excluded from type-checking and linting.

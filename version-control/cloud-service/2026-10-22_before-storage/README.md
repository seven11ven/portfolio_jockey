# Backup: before file storage (plan step 5)

Snapshot taken on 2026-10-22 before the file storage step changed these files.
They match commit `cad8e9d` ("Fix sign-out in Codespaces and log mockup approval").

- `src/db/schema.ts`: before the `deleted_objects` table was added.
- `src/lib/env.ts`: R2 variables were still optional.
- `.env_example`: before the R2 setup notes were updated.
- `src/proxy.ts`: matched /api routes other than /api/auth.

To restore a file, copy it back to the same path in the repo root. Restoring
`schema.ts` also requires rolling back migration `0001` in the database.

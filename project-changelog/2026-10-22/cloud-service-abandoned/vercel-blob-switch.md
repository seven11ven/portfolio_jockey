# File storage switched to Vercel Blob (private store, Hobby plan)

**Date:** 2026-10-22
**Time:** 2026-10-22 06:14 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Why
Cloudflare R2 and Backblaze B2 both required payment details, which conflicts with the Budgeting guideline. These points come from Vercel's own documentation, checked directly:
- [Hobby plan](https://vercel.com/docs/plans/hobby): "The Hobby plan is free". A card is only requested when upgrading to Pro.
- [Vercel Blob pricing](https://vercel.com/docs/vercel-blob/usage-and-pricing): Hobby includes 1 GB of storage, 10 GB of data transfer, 2,000 advanced operations and 10,000 simple operations per month. Over a limit, "you will not pay for any additional usage", but Blob access is blocked for 30 days.
- [Private storage](https://vercel.com/docs/vercel-blob/private-storage) and [signed URLs](https://vercel.com/docs/vercel-blob/vercel-signed-urls) support private files with time-limited links.

## Change
- **Dependencies:** added `@vercel/blob`, pinned exactly to **2.8.0** (released 2026-08-10). The newer 2.8.1 and 2.8.2 are recent, non-security patches. Removed `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner`, which are no longer used. `npm audit`: unchanged, with only the known `braces` issue in the ESLint toolchain.
- **`src/lib/object-storage.ts`** was rewritten for Vercel Blob:
  - Upload permissions use `issueSignedToken` with exactly one pathname, one content type and the approved maximum size. Vercel enforces these on the upload itself. Links last 15 minutes, with no overwrite and no random suffix.
  - View links use `presignUrl` GET, valid for 10 minutes and fetched straight from the store, so no app function streams large videos. They're signed with one read-only token kept in server memory and renewed daily, so the secret half never leaves the server.
  - `?download=1` is appended for downloads. Whether it works on presigned private links is still **unverified**.
  - `head` reads file info, and `del` deletes files. Deletes are free.
- **New `src/lib/blob-usage.ts`**, a free-allowance guard. It records estimated Blob usage over a rolling 30 days in a new `blob_usage_events` table (migration `0003`), and refuses actions past 90% of any Hobby limit: 1,800 advanced operations, 9,000 simple operations, 9 GB of transfer. Estimates are worst-case (every view counted as an uncached full download). A database lock makes reservations safe under parallel requests.
- **`src/lib/storage.ts`:**
  - Pathnames are now `userId/projectId/uuid/clean-name`. The random uuid folder keeps them unique and unguessable. The cleaned name (letters, numbers, dots, dashes and underscores only, never starting with a dot) gives downloads a sensible file name. The display name keeps the original characters.
  - Files over 100 MB upload in 8 MiB parts, as Vercel recommends. The usage guard counts the operations each upload uses.
  - New `authorizeUpload` grants upload permission only for the signed-in user's own pending file, at the exact pathname, within 15 minutes, in the expected single or multipart mode.
  - Cleanup also prunes old usage records.
- **API:**
  - `POST /api/uploads` returns `{ fileId, pathname, multipart }`.
  - New `POST /api/uploads/permission` wraps the SDK's `handleUploadPresigned` for the browser's `uploadPresigned()`. It accepts only "generate upload link" requests, checks the origin and session, and doesn't use Vercel's upload-completed webhook.
  - `/complete` and `/api/files/{id}` work as before. The free-allowance guard answers 429.
- **Settings:** the `STORAGE_*` settings were replaced by `BLOB_READ_WRITE_TOKEN` (local) or `BLOB_STORE_ID` (on Vercel). One of them is required. The default `STORAGE_QUOTA_BYTES` is now 900 MB.
- **Docs:** added `docs/setup/03-vercel-blob.md`, covering the cost and limits quoted from Vercel, a private store, the token for local development and recovery. Removed the never-committed Backblaze guide, and updated `01-neon.md` and `.env_example`.

## Version control
- `version-control/2026-10-22_before-vercel-blob/` holds the Backblaze (S3) versions of every changed file, plus `package.json` and `package-lock.json`. They were never committed, so the backup is the only copy. No secrets are included.

## Verification
- `npx tsc --noEmit`, `npx eslint` and `npm run build` pass.
- **Storage logic test, 27 of 27 passed:** run against real Neon with throwaway users and an in-memory stand-in for Vercel Blob, swapped in by a test-only loader outside the repo. It covers:
  - Type, size and ownership rules, and pathname cleaning.
  - The permission step refusing the wrong user, the wrong pathname, the wrong multipart mode, a bad id, and an expired 15-minute window.
  - Exact type and size in the upload permission.
  - Owner-only completion and views, and read-token reuse.
  - Mismatch cleanup.
  - Multipart operation counting: a 200 MB upload counts 28 operations.
  - The 900 MB-style storage quota (tested with a 300 MB quota).
  - **The usage guard refusing a view near the 10 GB limit, and 5 parallel reservations letting exactly 1 through.**
  - Delete, retention and purge.
  All test rows and usage records were removed afterwards.
- HTTP checks on a production build (port 3100, closed afterwards). The permission route blocked other sites with 403 and refused signed-out requests with 401. The other storage routes returned 401 when signed out.
- Migration `0003` was applied to Neon, which now has 4 migrations.

## Still to verify with the real Blob store
- A real upload through `uploadPresigned`, both single and multipart.
- Vercel rejecting a wrong content type or an oversized upload.
- `head` and `del` on a private store.
- View links, including video seeking, and whether `?download=1` survives the signature.
- Whether `issueSignedToken` shows up in Vercel's usage dashboard. The guard already counts it as an advanced operation to be safe.

## Impacts
- The owner must create a Vercel Hobby project, then a **private** Blob store, and copy `BLOB_READ_WRITE_TOKEN` into `.env`. See `docs/setup/03-vercel-blob.md`.
- Total file storage is capped at 900 MB, because of the 1 GB Hobby allowance.

# File storage with Cloudflare R2 (plan step 5)

**Date:** 2026-10-22
**Time:** 2026-10-22 02:29 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Change
- **R2 client** in `src/lib/r2.ts`, using the AWS S3 SDK, which R2 is compatible with.
  - Upload links last 15 minutes. The file's exact size and type are signed into the link, so R2 rejects anything else.
  - Download links last 10 minutes. The server fixes the content type and file name in the link. The UTF-8 file name has a safe ASCII fallback.
  - Checksum fields are only added when required, because browsers can't send them through presigned links.
  - Path-style URLs (`account.r2.cloudflarestorage.com/bucket/key`).
- **File rules** in `src/lib/file-types.ts`: allowed types (images, audio, video, PDF, plain text, Markdown, CSV), the 500 MB per-file limit, and file-name cleaning. SVG and HTML are blocked because they can carry scripts.
- **Storage logic** in `src/lib/storage.ts`. Every function is scoped to the signed-in user.
  - `createUpload` checks the type, size and entry ownership, then reserves quota and creates a `pending` file row with a random key. The quota check runs in one transaction behind a per-user database lock, so parallel uploads can't exceed the limit.
  - `completeUpload` asks R2 for the stored object's size and type, and only marks the file `ready` if both match. A mismatch deletes the upload.
  - `getDownloadUrl` only works for the owner's `ready` files.
  - `deleteEntry` and `deleteProject` move the files' records into `deleted_objects` and delete the rows in one transaction.
  - `cleanUpStorage` removes uploads never finished within 24 hours, and permanently deletes R2 objects whose 7-day retention has passed. It runs in the background after uploads.
- **API routes:**
  - `POST /api/uploads` starts an upload.
  - `POST /api/uploads/{fileId}/complete` finishes one.
  - `GET /api/files/{fileId}` redirects to a short-lived view link. Adding `?download=1` makes it a download.
  - The upload routes reject requests from other websites by checking the Origin header against `BETTER_AUTH_URL` and `TRUSTED_ORIGINS`. All routes return 401 JSON when not signed in. Shared helpers are in `src/lib/api.ts`.
- **Database:** new `deleted_objects` table, in migration `drizzle/0001_deleted_objects.sql`, applied to Neon. It deliberately has no foreign key, so cleanup still works if a user is deleted.
- **Proxy:** `src/proxy.ts` now skips every `/api` route. Each API route checks the login itself and answers with JSON instead of a redirect.
- **Environment:** the R2 variables are now required and validated (account ID format, bucket name format). New optional `R2_ENDPOINT` for local S3-compatible test servers. `.env_example` is updated.
- **Docs:** added `docs/setup/03-cloudflare-r2.md`, covering the private bucket, the CORS policy, a bucket-only API token, the cost note, how deleting works, and how to recover a deleted file.

## Change from the approved plan
- **The R2 bucket lock was replaced by an app-level 7-day retention.** An R2 bucket lock protects objects for a set time after *upload*, not after deletion. A file uploaded a month ago could still be deleted for good immediately. The app now keeps every deleted file in R2 for 7 days after deletion, and the files keep counting toward the quota until they're purged.
- **"Export project" moves to step 6.** It needs UI, and zipping large videos inside a Vercel function would hit time and memory limits. The design will be decided in step 6.

## Version control
- Backed up `src/db/schema.ts`, `src/lib/env.ts`, `src/proxy.ts` and `.env_example` to `version-control/2026-10-22_before-storage/`.

## Verification
- `npm run lint`, `npx tsc --noEmit` and `npm run build` pass.
- **Storage logic test, 34 checks:** run against the real Neon database with throwaway test users, and Moto (a local S3 simulator, outside the repo) standing in for R2. 33 passed:
  - Type, size, ownership and malformed-id rules.
  - File-name cleaning and random keys.
  - Pending files aren't viewable.
  - Completing before the upload exists is refused.
  - A browser-style upload through the link works.
  - Downloads return the same bytes. Other users can't complete or download.
  - A mismatched upload is removed.
  - **5 parallel uploads against a 100-byte quota: exactly 2 allowed.**
  - Deletes keep files during retention and purge them after it.
  - Abandoned uploads are removed.
  - Project delete cascades.
- **1 check couldn't pass on Moto:** the download's `Content-Disposition` header. Moto ignores response overrides. The generated link does carry the correct header, and it will be rechecked on real R2.
- All test rows were removed from Neon, with 0 left. The Moto server (port 5055) and the test server (port 3100) were stopped, and both ports were confirmed closed.
- HTTP checks on a production build:
  - An upload request from another site was blocked with 403.
  - An upload request with no Origin header was blocked with 403.
  - Requests while not signed in got 401.
  - A page visited while not signed in redirected to `/login`.
- `npm audit`: unchanged. Only the known `braces` issue in the ESLint toolchain remains.

## Impacts
- **The app now needs the R2 variables to start.** Until `.env` has them, the dev server shows an "Invalid environment variables" error. See `docs/setup/03-cloudflare-r2.md`.
- The owner must create the private bucket, its CORS policy and a bucket-only token.
- Once R2 is set up, run a real-R2 smoke test to confirm the size-locked links, the download header and CORS.
- No UI yet. The upload window from the approved mockup is built in step 6.

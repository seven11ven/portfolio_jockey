# Project scaffold (plan step 2)

**Date:** 2026-10-22
**Performed by:** Claude Code
**Approved by:** project manager (UI mockups approved, go-ahead given for setup)

## Change
- Generated a Next.js 16 app (App Router, TypeScript, Tailwind CSS 4, ESLint) with `create-next-app` in a temporary folder outside the repo, then copied it in. No existing file was overwritten.
  - Added `package.json`, `package-lock.json`, `next.config.ts`, `tsconfig.json`, `eslint.config.mjs`, `src/app/`, and `public/`.
  - Kept the existing `README.md`. The generated README was discarded.
- Installed app libraries:
  - `drizzle-orm` and `@neondatabase/serverless` for the Neon Postgres database.
  - `drizzle-kit` (dev) for database migrations.
  - `better-auth` for GitHub sign-in.
  - `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner` for private Cloudflare R2 file storage.
  - `zod` for input validation.
- Added a `typecheck` script (`next typegen && tsc --noEmit`). It generates Next.js route types before type-checking, so it works on a fresh clone.
- Filled `.env_example` with every variable the app will need. All values are empty, and each one has comments explaining what it does and how to set it up.
- Merged the generated `.gitignore` rules into the root `/.gitignore`, following the single `.gitignore` rule. The generated file was discarded. New rules cover Yarn and pnpm files. Redundant env rules were removed because `.env*` with the `!.env_example` exception already covers them.
- Appended the Next.js managed block to `AGENTS.md`. `next dev` inserts this block automatically. It tells agents to read the bundled Next.js 16 docs in `node_modules/next/dist/docs/`, because the APIs differ from older versions.
- Synced agent files with the new "Always clean up loose ends" security rule (close ports and connections when they're no longer needed).

## Security review
- `npm audit` after setup:
  - **Fixed:** `esbuild` 0.18 (moderate, dev-server request issue, GHSA-67mh-4wv8-2f99), pulled in by `drizzle-kit`. An `overrides` entry in `package.json` forces the patched 0.25 line. `drizzle-kit` still works.
  - **Accepted for now:** `braces` (high, denial of service from deeply nested patterns, GHSA-vfj7-8cjw-p6xm), used by the ESLint plugin for Next.js. Every published version is affected, so no fix exists. It runs only during linting on our own code and never ships to the live site. `npm audit fix --force` was **not** run, because it would downgrade the Next.js lint config to version 14. Re-check when a patch is released.
- npm blocked install scripts for `unrs-resolver` and `esbuild`. Neither is needed, because their native binaries are already installed through optional dependencies. Both stay blocked.
- No ports or servers were left running.

## Verification
- `npm run lint` passes.
- `npm run typecheck` passes.
- `npm run build` passes.
- `.env`, `.next/`, `node_modules/`, and `next-env.d.ts` are all ignored by Git.

## Impacts
- This is the first application build, so no prior component versions existed to store in `version-control/`. Later changes to these files must be backed up there first.
- The site still shows the default Next.js starter page. The real UI is built in plan step 6, following the approved mockups.

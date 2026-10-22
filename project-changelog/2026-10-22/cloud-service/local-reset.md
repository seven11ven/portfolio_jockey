# Reset to a clean slate for a fully local app

**Date:** 2026-10-22
**Time:** 2026-10-22 12:24 UTC
**Performed by:** Claude Code
**Requested by:** project manager

## Why
The project manager decided Portfolio Jockey will be a fully local app instead of a cloud app. Login (GitHub via Better Auth), the cloud database (Neon) and cloud file storage (Vercel Blob) are no longer needed. Every dependency and all app code was removed so a new plan can choose the stack from scratch.

## Change
- **App code removed:** `src/`, `drizzle/` (migrations 0000 to 0003) and `public/`.
- **Dependencies removed:** `package.json` and `package-lock.json`, so every package is gone, including Next.js, React, Tailwind CSS, ESLint, zod, Drizzle, Better Auth, the Neon driver and `@vercel/blob`. The local `node_modules/` was deleted.
- **Config removed:** `next.config.ts`, `tsconfig.json`, `eslint.config.mjs` and `drizzle.config.ts`.
- **Setup guides removed:** `docs/setup/01-neon.md`, `02-github-login.md` and `03-vercel-blob.md`. The folder is now empty and was removed. The guides remain in Git history at commit `d6f8220`.
- **`.env_example` emptied:** only the "HOW TO USE" header remains. The database, auth, storage and limits variables were removed.
- **`.devcontainer/devcontainer.json`:** removed `postCreateCommand: npm ci`, which would fail without a `package.json`. Also removed the Next.js port 3000 forward and the ESLint and Tailwind extension recommendations. The Node 24 image and the non-root `node` user stay until a stack is chosen.
- **`AGENTS.md`:** removed the Next.js managed block. It pointed agents to `node_modules/next/dist/docs/`, which no longer exists. The guidelines didn't change, so the other agent files needed no sync.
- **Untracked build output deleted:** `.next/`, `next-env.d.ts` and `tsconfig.tsbuildinfo`.
- **Kept:** all mockups in `project-mockups/`, the guidelines, the agent files, `.gitignore`, the changelogs and the earlier backups. The local `.env` was not touched.

## Version control
- Backed up every removed application file, plus the old `.env_example` and `devcontainer.json`, to `version-control/2026-10-22_before-local-reset/`. A README there explains how to restore them. The backup was checked against the tracked files (all 47 present) and scanned for secrets. The only match was a setup command in a comment, not a value. `.env` was not backed up.

## Verification
- `git ls-files` lists no app code, package, config or setup-guide files.
- No live references to the removed packages or to `docs/setup/` remain outside `version-control/` and `project-changelog/`.
- No ports or servers were started.

## Owner cleanup outside the repo
These close off the cloud resources and revoke the credentials in the local `.env`:
1. **Neon:** delete the Portfolio Jockey project (project Settings > Delete project).
2. **GitHub:** delete each Portfolio Jockey OAuth App (Settings > Developer settings > OAuth Apps). Check Settings > Applications > Authorized OAuth Apps too.
3. **Vercel:** delete the private Blob store and the Vercel project, if they were created.
4. **Local `.env`:** empty or delete it once 1 to 3 are done.
5. **Codespaces:** stop any codespace still forwarding port 3000.

**Done by the owner:** emptied the local `.env`, deleted the GitHub OAuth App, deleted the Neon project, and stopped the port 3000 forwarding. Vercel wasn't mentioned. If a Blob store or Vercel project was ever created, it still needs deleting.

## Impacts
- The app no longer builds or runs. There's nothing to run until the new plan is built.
- Neon, GitHub OAuth and Vercel Blob are no longer used.
- The mockups for login, the login error and the account menu were kept but no longer apply to a local app. The new plan should decide what happens to them, and to the dashboard storage meter.
- `.gitignore` still holds Next.js and Vercel entries. They do no harm, and the new plan can adjust them once the stack is known.

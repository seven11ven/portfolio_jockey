# GitHub login (plan step 4)

**Date:** 2026-10-22
**Time:** 2026-10-22 01:56 UTC
**Performed by:** Claude Code
**Approved by:** project manager (go-ahead given after the Neon tables were created)

## Change
- **Better Auth server setup** in `src/lib/auth.ts`:
  - GitHub is the only sign-in method, with default scopes only (`read:user user:email`). No passwords are stored.
  - A `validateUserInfo` hook allows only verified emails listed in `ALLOWED_EMAILS`. It runs on sign-up, account linking and every GitHub sign-in, with the fresh email from GitHub.
  - GitHub OAuth tokens are encrypted before they're stored.
  - Login errors redirect to `/login`, which shows a friendly message.
- **Auth API route** at `src/app/api/auth/[...all]/route.ts`.
- **Session check** in `src/lib/session.ts`: `getCurrentUser()` and `requireUser()`. They re-check the allowlist on every request, so removing an email locks that account out right away. They return only id, name, email and image, never the raw session.
- **Proxy** at `src/proxy.ts`, which Next.js 16 uses in place of middleware. It redirects visitors without a login cookie to `/login`. It's only a fast pre-check. `requireUser()` is the real security check.
- **Login page** at `src/app/login/page.tsx`, built to the approved mockup, with an error message state. Unknown error codes show a generic message, so nothing from the URL is shown on the page as-is.
- **Temporary signed-in page** at `src/app/page.tsx`, with a Sign out button, for testing login. The dashboard replaces it in plan step 6.
- **Environment check** in `src/lib/env.ts`: the login variables are now required and validated. `ALLOWED_EMAILS` becomes a lowercase list.
- **Theme:** `src/app/globals.css` now uses the mockup color tokens in light and dark. `layout.tsx` uses system fonts like the mockups, so there are no Google Fonts requests. The page title is "Portfolio Jockey", and search engines are asked not to index the site.
- **Next.js 16 Cache Components:** parts of a page that read the login cookie render inside `<Suspense>` boundaries, following the bundled Next.js guide "Authentication with Cache Components".
- **Docs:** added `docs/setup/02-github-login.md`. `.env_example` now explains `BETTER_AUTH_URL` for local, Codespaces and Vercel use. It also gives a command that writes `BETTER_AUTH_SECRET` into `.env` without printing it.
- **Floor Planning mockups** for UI the approved mockups didn't cover:
  - `project-mockups/login-error.html`: login error message (already built into the login page).
  - `project-mockups/account-menu.html`: avatar menu with Sign out (planned for step 6).
  - Small `styles.css` change, so the account menu stays on screen on phones.

## Version control
- Backed up `src/app/layout.tsx`, `globals.css`, `page.tsx` and `src/lib/env.ts` to `version-control/2026-10-22_before-auth/` before changing them.

## Verification
- `npm run lint`, `npm run typecheck` and `npm run build` pass.
- Ran the production build briefly on a local-only port with fake GitHub settings:
  - Visiting `/` without a login cookie redirected to `/login`.
  - The login page rendered. The `not_allowed` error showed its message. An injected `<script>` in the URL showed the generic message, and the script wasn't present on the page.
  - Starting GitHub sign-in produced a github.com link with only `read:user user:email` scopes, the correct callback URL and a state value.
  - An outside `callbackURL` was rejected (`INVALID_CALLBACK_URL`), which blocks open redirects.
  - A request from another site carrying a login cookie was rejected with 403. The same request from the app's own address was allowed.
  - A forged session cookie didn't get past `requireUser()`, which redirected to `/login`.
  - A GitHub callback with a fake state redirected to `/login?error=state_mismatch`.
  - The server log contained no connection strings.
- Cleanup: the test server was stopped, and port 3100 was confirmed closed. The two temporary sign-in records the tests created in Neon were deleted, leaving no users, sessions or sign-in records.
- `npm audit`: unchanged. Only the known `braces` issue in the ESLint toolchain remains.

## Impacts
- The owner must create a GitHub OAuth App and fill in the login variables in `.env`. See `docs/setup/02-github-login.md`.
- The app now refuses to start without valid login variables, including on Vercel.
- Two new mockups need the project manager's approval. The login error is already built, and the account menu is planned for step 6.

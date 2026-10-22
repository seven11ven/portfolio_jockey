# Backup: before the sign-out fix

Snapshot taken on 2026-10-22 before fixing sign-out in GitHub Codespaces.
These files match the state after plan step 4 (GitHub login).

- `src/lib/auth.ts`: trusted only BETTER_AUTH_URL as an origin.
- `src/lib/env.ts`: had no TRUSTED_ORIGINS variable.
- `src/components/sign-out-button.tsx`: went to /login even when sign-out failed.
- `.env_example`: had no TRUSTED_ORIGINS entry.

To restore a file, copy it back to the same path in the repo root.

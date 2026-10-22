# Dev container for DevPod, Coder and other environments

**Date:** 2026-10-22
**Time:** 2026-10-22 06:23 UTC
**Performed by:** Claude Code
**Requested by:** project manager

## Change
Added `.devcontainer/devcontainer.json`, the standard dev container file (https://containers.dev) read by DevPod, Coder, GitHub Codespaces and VS Code Dev Containers. It lets the project move off Codespaces to an open-source, self-run environment.
- **Image:** `mcr.microsoft.com/devcontainers/typescript-node:4-24-bookworm`, the official Microsoft image (image version 4, Node.js 24, Debian Bookworm). The tag was confirmed in the registry's tag list.
- **Setup:** `postCreateCommand: npm ci` installs the exact locked dependency versions.
- **Ports:** forwards port 3000 for the Next.js dev server, with a reminder to keep it private and close it when done.
- **Editor:** recommends the ESLint and Tailwind CSS VS Code extensions.
- **User:** runs as the image's non-root `node` user.
- Contains no secrets. `.env` must be created in each new environment from `.env_example`.

## Verification
- The file parses as valid JSONC.
- The image runs Node v24.16.0 and npm 11.13.0, and has the `node` user.
- `npm ci` succeeded inside the image as the `node` user, on a copy of `package.json` and `package-lock.json` in a temporary folder outside the repo, with exit code 0 and 418 packages installed.
- The temporary folder and the downloaded image were removed afterwards. No containers were left running.

## Notes
- The install reported `eslint@9.39.5` as no longer supported upstream. It's a development-only tool. Review it in a future dependency update.
- Outside Codespaces, `BETTER_AUTH_URL` and the GitHub OAuth callback change to the new address, such as `http://localhost:3000`, and `TRUSTED_ORIGINS` should be left empty.

## Impacts
- No application code changed, and this is a new file, so no `version-control/` backup was needed.

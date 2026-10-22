# Cloud-era folders renamed to `cloud-service-abandoned`

**Date:** 2026-10-22
**Time:** 2026-10-22 14:25 UTC
**Performed by:** Claude Code
**Requested by:** project manager

## Change
The project manager marked the cloud version as abandoned. The three cloud-era folders now share one name with no spaces. A space in a path breaks unquoted shell commands.

| Before | After |
|---|---|
| `version-control/cloud-service/` (briefly `cloud-service (abandoned)/`) | `version-control/cloud-service-abandoned/` |
| `project-changelog/2026-10-22/cloud-service/` | `project-changelog/2026-10-22/cloud-service-abandoned/` |
| `project-mockups/cloud-service/` | `project-mockups/cloud-service-abandoned/` |

Live references were updated:
- `CLAUDE.md` (Repo conventions)
- the link in `project-mockups/index.html`

Older changelogs (`plan.md`, `ui-mockups.md`, `ai-agent-instructions.md`) still say `cloud-service/`. They're left as written, because they record what was done at the time.

## Verification
- **Pure renames:** each new folder was compared with the committed version of the old one (`git archive HEAD`), and all three are identical.
- Nothing inside the moved folders refers to its own path. The cloud mockups use no `../` links.
- The renamed backups were scanned for secrets. The `.env_example` values are empty, and the only email addresses are `example.com` placeholders.
- The folders were moved without staging.

## Impacts
- **No content changes.** Everything moved is already public in git history, so committing the rename exposes nothing new.
- Git will show the moves as deletions plus new files until they're staged together. Then it detects them as renames.
- Backups aren't needed. This only moves documentation and archived backups, and changes no application component.

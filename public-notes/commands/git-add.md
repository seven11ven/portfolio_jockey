# git add

| Command | What it stages |
|---|---|
| `git add -A` | Everything in the repo, from any folder (new, edited, and deleted files) |
| `git add .` | Everything in the current folder and below |
| `git add -u` | Edits and deletions to tracked files only, no new files |
| `git add <file-name>` | Just that one file |

- All forms respect `.gitignore`.
- From the repo root, `git add -A` and `git add .` do the same thing.
- Always run `git status` before committing. This repo is public.
- Unstage something by mistake: `git restore --staged <file-name>`

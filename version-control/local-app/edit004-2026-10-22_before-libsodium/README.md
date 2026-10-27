# Backup: before adding libsodium

Snapshot taken on 2026-10-22, before plan phase 4 (vault core) added libsodium to the dev container.

- `.devcontainer/setup.sh`: the setup script from plan phase 2, without the `libsodium23` package.
- `app/tool/check-privacy.sh`: the phase 3 privacy check, without the native-library check.

Phase 4 also created `app/lib/vault/`, `app/test/vault/` and `app/tool/allowed-native-libs.txt`, and changed `app/tool/check-privacy.sh`. To go back to the phase 3 app, delete those folders and that file, and copy `app/tool/check-privacy.sh` back from here.

## Restore
Copy `.devcontainer/setup.sh` and `app/tool/check-privacy.sh` back to the repo root, keeping their paths. `sudo apt-get remove libsodium23` removes the library from a running container.

No secrets are included.

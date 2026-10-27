# Backup: before the edit path check fix

Snapshot taken on 2026-10-23.

- `app/lib/services/native/gio_apps.dart`: before the shared-folder check also accepted the resolved path (`/run/flatpak/app/<id>/`, which `$XDG_RUNTIME_DIR/app/<id>` links to inside the sandbox).
- `app/tool/package-bundle.sh`: before release builds kept every icon (`--no-tree-shake-icons`).

## Restore
Copy the file back to the same path in the repo.

No secrets are included.

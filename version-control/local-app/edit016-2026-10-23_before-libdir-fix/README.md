# Backup: before the Flatpak libdir fix

Snapshot taken on 2026-10-23, after the first build on the PM's PC stopped because libplacebo installed into `lib64/`. Each file keeps its repo path.

- `packaging/flatpak/io.github.seven11ven.portfolio_jockey.yml`: before the meson and CMake modules were pinned to install into `lib/`.
- `packaging/flatpak/build.sh`: before it asked for a log-out only when `flatpak` itself was missing.

## Restore
Copy the files back to the same paths in the repo.

No secrets are included.

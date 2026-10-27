# Backup: before the mpv locale fix

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `app/linux/runner/my_application.cc`: before it reset `LC_NUMERIC` to `"C"` after GTK's startup, which libmpv needs. Without the reset, audio and video crashed on desktops with a non-C locale.

## Restore
Copy the file back to the same path in the repo.

No secrets are included.

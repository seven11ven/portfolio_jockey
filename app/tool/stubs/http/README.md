# Empty `http` stand-in

`file_selector_platform_interface` (part of the file picker) lists the `http` networking package as a dependency but never imports it. Portfolio Jockey never uses the network, and the project's rules keep networking packages out of the dependency tree entirely.

`app/pubspec.yaml` therefore replaces `http` with this empty package through `dependency_overrides`:
- No networking code is downloaded, and none is present.
- If anything ever does import `package:http`, the build fails with "Target of URI doesn't exist" instead of quietly gaining network access.

`tool/check-privacy.sh` fails if this folder ever holds anything except `pubspec.yaml` and this README.

Decided by the project manager on 2026-10-22 (plan phase 5).

# Center image file-type labels

**Time:** 2026-10-27 09:46 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- `TypeBadge` now centers the format label alone for raster and SVG files; other file types retain their icon-and-label layout.
- The project and folder grid mockups match, and the JPG/SVG full-preview artwork remains unchanged.
- Added a widget test verifying JPG and SVG labels are centered in the image cover and have no visible image icon.

## Backup
`version-control/local-app/edit042-2026-10-27_before-centered-image-badge/` contains the previous `common.dart` and folder UI test.

## Verification
The focused widget test passes; all 52 UI tests pass; `flutter analyze --fatal-infos --fatal-warnings` and `tool/check-privacy.sh` pass. The mockup page responds with HTTP 200.

## Impacts
Small visual change to image file cards. No dependencies or stored formats changed. **Not committed.**

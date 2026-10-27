#!/usr/bin/env bash
# Builds the release app bundle for the Flatpak and the "build kit" the
# project manager copies to their own PC (phase 8). Run from anywhere:
#
#   bash app/tool/package-bundle.sh
#
# 1. Runs every check first: the telemetry lockdown, the privacy check,
#    flutter analyze and the full test suite. Any failure stops here.
# 2. flutter build linux --release, then packs the bundle as a reproducible
#    tarball (sorted names, fixed owner and date) with its SHA-256.
# 3. Writes that SHA-256 into a copy of the manifest and packs the build kit:
#    the manifest, desktop file, metainfo, icon, bundle, build.sh and
#    TESTING.md (when present).
#
# Everything it makes goes in packaging/flatpak/dist/, which is git-ignored.
# Nothing is downloaded and nothing leaves this machine.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
app="$repo/app"
pkg="$repo/packaging/flatpak"
dist="$pkg/dist"
id=io.github.seven11ven.portfolio_jockey
version=$(sed -nE "s/^const String appVersion = '([^']+)';/\1/p" "$app/lib/app/version.dart")
[ -n "$version" ] || { echo "Could not read appVersion from lib/app/version.dart" >&2; exit 1; }
bundle_name="portfolio-jockey-bundle-$version-x86_64.tar.gz"
kit_name="portfolio-jockey-build-kit-$version"

if [ "$(uname -m)" != x86_64 ]; then
  echo "The first release is x64 only; this machine is $(uname -m)." >&2
  exit 1
fi

echo "== Checks"
bash "$repo/.devcontainer/check-lockdown.sh"
cd "$app"
bash tool/check-privacy.sh
flutter analyze --fatal-infos --fatal-warnings
flutter test

echo "== Release build"
flutter build linux --release
built="$app/build/linux/x64/release/bundle"
[ -x "$built/portfolio_jockey" ] || { echo "No release bundle at $built" >&2; exit 1; }

rm -rf "$dist"
mkdir -p "$dist/$kit_name"
# A fixed date, owner and order, so the same build gives the same tarball.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00Z' \
  -C "$built/.." -cf - bundle | gzip -n -9 > "$dist/$bundle_name"
bundle_sha=$(sha256sum "$dist/$bundle_name" | cut -d' ' -f1)

echo "== Build kit"
kit="$dist/$kit_name"
cp "$dist/$bundle_name" "$kit/"
cp "$pkg/$id.desktop" "$pkg/$id.metainfo.xml" "$pkg/$id.svg" "$pkg/build.sh" "$kit/"
[ -f "$pkg/TESTING.md" ] && cp "$pkg/TESTING.md" "$kit/"
grep -q '@BUNDLE_SHA256@' "$pkg/$id.yml" || { echo "The manifest has no @BUNDLE_SHA256@ placeholder" >&2; exit 1; }
sed -e "s/@BUNDLE_SHA256@/$bundle_sha/" -e "s/@BUNDLE_NAME@/$bundle_name/" "$pkg/$id.yml" > "$kit/$id.yml"
(cd "$kit" && sha256sum -- * > SHA256SUMS)
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00Z' \
  -C "$dist" -cf - "$kit_name" | gzip -n -9 > "$dist/$kit_name.tar.gz"

echo
echo "App bundle: $dist/$bundle_name"
echo "  SHA-256:  $bundle_sha"
echo "Build kit:  $dist/$kit_name.tar.gz"
echo "  SHA-256:  $(sha256sum "$dist/$kit_name.tar.gz" | cut -d' ' -f1)"
echo "Download the build kit through VS Code (right-click it in the Explorer, then Download)."

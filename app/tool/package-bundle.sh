#!/usr/bin/env bash
# Builds the release app bundle for the Flatpak and the "build kit" the
# project manager copies to their own PC (phase 8). Run from anywhere:
#
#   bash app/tool/package-bundle.sh
#
# 1. Runs every check first: the telemetry lockdown, the privacy check,
#    flutter analyze and the full test suite. Any failure stops here.
# 2. flutter build linux --release, then packs the bundle as a tarball with
#    its SHA-256. Packing adds no differences (sorted names, fixed owner and
#    date), but Flutter's own build output isn't guaranteed to be identical
#    between builds, so a rebuild may give a new checksum.
# 3. Writes that SHA-256 into a copy of the manifest and packs the build kit:
#    the manifest, desktop file, metainfo, icon, LICENSE, bundle, build.sh,
#    TESTING.md, docs/install.md (as INSTALL.md) and SOURCE_COMMIT.
# 4. Writes the app's own source (git archive of the commit it was built
#    from), which the AGPL requires offering with every release.
#
# It refuses to run with uncommitted changes, so the source archive matches
# the build exactly.
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

if [ -n "$(git -C "$repo" status --porcelain)" ]; then
  echo "There are uncommitted changes. Commit them first, so the source archive matches the build:" >&2
  git -C "$repo" status --short >&2
  exit 1
fi
commit=$(git -C "$repo" rev-parse HEAD)

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
# A fixed date, owner and order, so packing the same files gives the same tarball.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00Z' \
  -C "$built/.." -cf - bundle | gzip -n -9 > "$dist/$bundle_name"
bundle_sha=$(sha256sum "$dist/$bundle_name" | cut -d' ' -f1)

echo "== Build kit"
kit="$dist/$kit_name"
cp "$dist/$bundle_name" "$kit/"
cp "$pkg/$id.desktop" "$pkg/$id.metainfo.xml" "$pkg/$id.svg" "$pkg/build.sh" "$kit/"
cp "$pkg/TESTING.md" "$kit/"
cp "$repo/docs/install.md" "$kit/INSTALL.md"
cp "$repo/LICENSE" "$kit/"
echo "$commit" > "$kit/SOURCE_COMMIT"
grep -q '@BUNDLE_SHA256@' "$pkg/$id.yml" || { echo "The manifest has no @BUNDLE_SHA256@ placeholder" >&2; exit 1; }
sed -e "s/@BUNDLE_SHA256@/$bundle_sha/" -e "s/@BUNDLE_NAME@/$bundle_name/" "$pkg/$id.yml" > "$kit/$id.yml"
(cd "$kit" && sha256sum -- * > SHA256SUMS)
source_name="portfolio-jockey-source-$version"
git -C "$repo" archive --format=tar --prefix="$source_name/" "$commit" | gzip -n -9 > "$dist/$source_name.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00Z' \
  -C "$dist" -cf - "$kit_name" | gzip -n -9 > "$dist/$kit_name.tar.gz"

echo
echo "App bundle: $dist/$bundle_name"
echo "  SHA-256:  $bundle_sha"
echo "Build kit:  $dist/$kit_name.tar.gz"
echo "  SHA-256:  $(sha256sum "$dist/$kit_name.tar.gz" | cut -d' ' -f1)"
echo "App source: $dist/$source_name.tar.gz (commit $commit)"
echo "  SHA-256:  $(sha256sum "$dist/$source_name.tar.gz" | cut -d' ' -f1)"
echo "Download the build kit through VS Code (right-click it in the Explorer, then Download)."

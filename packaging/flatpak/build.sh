#!/usr/bin/env bash
# Builds and installs the Portfolio Jockey Flatpak on your own PC (phase 8).
# Run it from the unpacked build kit folder:
#
#   bash build.sh
#
# What it does, in order:
#  1. Checks that flatpak and flatpak-builder are installed.
#  2. Checks every kit file against SHA256SUMS.
#  3. Adds the Flathub remote for your user (if it isn't there yet) and
#     installs the freedesktop 26.08 Platform and Sdk from it. These, and the
#     library sources the manifest lists (each pinned by SHA-256), are the only
#     downloads. The app itself never gets network access.
#  4. Builds the app with flatpak-builder into a local repo (./repo), together
#     with the exact sources of every module.
#  5. Makes two single files and prints their SHA-256:
#     - portfolio-jockey-<version>-x86_64.flatpak, the app
#     - portfolio-jockey-<version>-sources.flatpak, the sources of the
#       libraries inside it. The GPL requires offering these with every copy
#       of the app, so a release always publishes both.
#     Then installs the app for your user from that very .flatpak file, so
#     you test what other people will get. Your vault and settings are kept.
#  6. Prints the app's sandbox permissions, so you can see there's no network,
#     and checks that the license files were installed.
#
# Nothing needs sudo except installing flatpak itself (step 1 tells you how).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
id=io.github.seven11ven.portfolio_jockey
manifest="$id.yml"
version=$(sed -nE 's/.*portfolio-jockey-bundle-([0-9][^-]*)-x86_64\.tar\.gz.*/\1/p' "$manifest" | head -n1)
bundle_file="portfolio-jockey-$version-x86_64.flatpak"
sources_file="portfolio-jockey-$version-sources.flatpak"
flathub_repo=https://dl.flathub.org/repo/flathub.flatpakrepo

say() { printf '\n== %s\n' "$1"; }

say "1. Tools"
if [ "$(uname -m)" != x86_64 ]; then
  echo "This build is x64 only; this PC is $(uname -m)." >&2
  exit 1
fi
missing=()
command -v flatpak >/dev/null || missing+=(flatpak)
command -v flatpak-builder >/dev/null || missing+=(flatpak-builder)
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing: ${missing[*]}. Install them with:"
  echo "  sudo apt install ${missing[*]}"
  if [[ " ${missing[*]} " == *" flatpak "* ]]; then
    echo "then log out and back in once (Flatpak needs that the first time), and run this script again."
  else
    echo "then run this script again."
  fi
  exit 1
fi
echo "flatpak $(flatpak --version | awk '{print $2}'), flatpak-builder $(flatpak-builder --version | awk '{print $2}')"

say "2. Kit files"
sha256sum --check --strict SHA256SUMS

say "3. Runtime from Flathub"
flatpak remote-add --user --if-not-exists flathub "$flathub_repo"
flatpak install --user --noninteractive flathub org.freedesktop.Platform//26.08 org.freedesktop.Sdk//26.08

say "4. Build"
flatpak-builder --force-clean --bundle-sources --repo=repo --install-deps-from=flathub build-dir "$manifest"

say "5. Single files, then install"
flatpak build-bundle repo "$bundle_file" "$id" --runtime-repo="$flathub_repo"
flatpak build-bundle --runtime repo "$sources_file" "$id.Sources"
echo "Made $bundle_file"
echo "  SHA-256: $(sha256sum "$bundle_file" | cut -d' ' -f1)"
echo "Made $sources_file"
echo "  SHA-256: $(sha256sum "$sources_file" | cut -d' ' -f1)"
flatpak install --user --reinstall --noninteractive "$bundle_file"

say "6. Checks"
echo "Sandbox permissions (there must be no 'network' under [Context] shared=):"
flatpak info --user --show-permissions "$id"
if flatpak info --user --show-permissions "$id" | grep -E '^shared=' | grep -q network; then
  echo "WARNING: the app has network access. Don't use this build; report it." >&2
  exit 1
fi
licenses=$(flatpak run --command=ls "$id" "/app/share/licenses/$id" 2>/dev/null | tr '\n' ' ')
echo "License files installed for: ${licenses:-none}"
for module in libsodium poppler portfolio_jockey; do
  if [[ " $licenses " != *" $module "* ]]; then
    echo "WARNING: no license files for $module. Don't share this build; report it." >&2
    exit 1
  fi
done
if command -v appstreamcli >/dev/null; then
  appstreamcli validate --no-net "$id.metainfo.xml" || echo "Note: appstreamcli reported problems with the metainfo (above)."
fi
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$id.desktop" || echo "Note: desktop-file-validate reported problems (above)."
fi

echo
echo "Done. Start the app from your applications menu, or with:"
echo "  flatpak run $id"
echo "If it isn't in the menu yet, log out and back in once: the menu only sees"
echo "apps installed for your user after Flatpak has set that up at login."
echo "Then work through TESTING.md."

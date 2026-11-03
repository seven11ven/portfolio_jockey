#!/usr/bin/env bash
# Portfolio Jockey: one-time dev container setup (postCreateCommand).
# Installs the Linux desktop build tools and a pinned Flutter SDK, with
# telemetry locked down BEFORE Flutter or Dart run for the first time.
# Safe to re-run. Linux only: the Android port is on hold.
set -euo pipefail

# Flutter stable 3.47.7 (Dart 3.13.5), released 2026-10-08. The checksum comes
# from Flutter's official release list:
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
FLUTTER_VERSION="3.47.7"
FLUTTER_ARCHIVE="stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SHA256="af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230"
FLUTTER_DIR="$HOME/flutter"

here="$(cd "$(dirname "$0")" && pwd)"

# 1. Telemetry lockdown first, and these variables for the rest of this script.
bash "$here/lockdown.sh"
export FLUTTER_SUPPRESS_ANALYTICS=true DASH__SUPPRESS_ANALYTICS=true DO_NOT_TRACK=1

# 2. Linux desktop build tools, from https://docs.flutter.dev/platform-integration/linux/setup
#    (Debian packages; none of them collect telemetry). libsodium23 is the
#    crypto library the vault calls through dart:ffi (see docs/dependencies.md).
#    libpoppler-glib8 renders PDF previews through our own dart:ffi. (Audio
#    and video play in the desktop's own player, so libmpv isn't needed.)
#    xvfb, xdotool and xclip run the real app on a virtual screen for
#    app/tool/desktop-check.sh (Xvfb with -nolisten tcp: a local socket only);
#    python3-yaml, appstream and desktop-file-utils check the Flatpak files
#    (appstreamcli is always run with --no-net). gdb gives stack traces of a
#    stuck app (run with DEBUGINFOD_URLS= so it never downloads symbols).
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev \
  libsodium23 libpoppler-glib8 \
  xvfb xdotool xclip python3-yaml appstream desktop-file-utils gdb \
  curl git unzip xz-utils ca-certificates

# 3. Pinned Flutter SDK, checksum verified before anything is unpacked.
if [ -x "$FLUTTER_DIR/bin/flutter" ] && grep -q "\"frameworkVersion\": \"$FLUTTER_VERSION\"" "$FLUTTER_DIR/bin/cache/flutter.version.json" 2>/dev/null; then
  echo "Flutter $FLUTTER_VERSION already installed."
else
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --proto '=https' --tlsv1.2 -o "$tmp/flutter.tar.xz" \
    "https://storage.googleapis.com/flutter_infra_release/releases/$FLUTTER_ARCHIVE"
  echo "$FLUTTER_SHA256  $tmp/flutter.tar.xz" | sha256sum -c -
  rm -rf "$FLUTTER_DIR"
  tar -xf "$tmp/flutter.tar.xz" -C "$HOME"
fi
export PATH="$PATH:$FLUTTER_DIR/bin"

# 4. Remove telemetry from the Flutter tool's own source (layer 5), then force
#    the tool to recompile from the patched source. The patch is written for
#    FLUTTER_VERSION. If it no longer applies cleanly, stop instead of carrying on.
patch_file="$here/flutter-remove-telemetry.patch"
if git -C "$FLUTTER_DIR" apply --reverse --check "$patch_file" 2>/dev/null; then
  echo "Flutter telemetry patch already applied."
else
  git -C "$FLUTTER_DIR" apply --check "$patch_file" || {
    echo "The Flutter telemetry patch doesn't apply to Flutter $FLUTTER_VERSION. Update the patch before upgrading." >&2
    exit 1
  }
  git -C "$FLUTTER_DIR" apply "$patch_file"
  rm -f "$FLUTTER_DIR/bin/cache/flutter_tools.snapshot" "$FLUTTER_DIR/bin/cache/flutter_tools.stamp"
  echo "Flutter telemetry patch applied; the tool recompiles on its next run."
fi

# 5. Only the Linux desktop target; every other platform off.
flutter config --enable-linux-desktop --no-enable-android --no-enable-web \
  --no-enable-ios --no-enable-macos-desktop --no-enable-windows-desktop
flutter precache --linux
flutter --version

# 6. Prove nothing was or can be reported.
bash "$here/check-lockdown.sh"

#!/usr/bin/env bash
# Portfolio Jockey: block Flutter, Dart and editor telemetry.
#
# Runs before Flutter is installed (from setup.sh) and again on every container
# start (postStartCommand), because Docker rewrites /etc/hosts on start.
# Safe to run any number of times.
#
# Sources checked on 2026-10-22:
# - dart-lang/tools pkgs/unified_analytics (constants.dart, utils.dart,
#   initializer.dart, config_handler.dart): endpoint www.google-analytics.com,
#   config file ~/.dart-tool/dart-flutter-telemetry.config with "reporting=0",
#   legacy opt-out files, and the DASH__SUPPRESS_ANALYTICS variable.
# - flutter/flutter packages/flutter_tools (reporting/unified_analytics.dart,
#   reporting/crash_reporting.dart): FLUTTER_SUPPRESS_ANALYTICS, and crash
#   reports to clients2.google.com/cr/report.
# - Dart-Code/Dart-Code src/extension/analytics.ts: the VS Code extension stays
#   off when DO_NOT_TRACK=1 or the config file says "reporting=0".
set -euo pipefail

BLOCKED_HOSTS=(
  www.google-analytics.com
  ssl.google-analytics.com
  region1.google-analytics.com
  analytics.google.com
  clients2.google.com
)

# 1. Point telemetry hostnames at nowhere, for both IPv4 and IPv6, so nothing can
#    reach them even if every other layer failed.
for host in "${BLOCKED_HOSTS[@]}"; do
  for addr in 0.0.0.0 ::; do
    if ! grep -qE "^${addr//./\\.}[[:space:]]+${host//./\\.}([[:space:]]|$)" /etc/hosts; then
      echo "${addr} ${host}  # portfolio-jockey telemetry block" | sudo tee -a /etc/hosts >/dev/null
    fi
  done
done

# 2. Write the opt-out before any Dart or Flutter tool runs. This way no tool
#    ever has a "first run" and never sends the one-time opt-out event that
#    `flutter --disable-analytics` would.
mkdir -p "$HOME/.dart-tool" "$HOME/.dart" "$HOME/.flutter-devtools"
config="$HOME/.dart-tool/dart-flutter-telemetry.config"
if [ ! -f "$config" ]; then
  cat > "$config" <<'EOF'
# Flutter and Dart telemetry reporting configuration file.
# Disabled by Portfolio Jockey's dev container (.devcontainer/lockdown.sh).
reporting=0
EOF
else
  # Turn any "reporting=1" off, and make sure a "reporting=0" line exists.
  sed -i 's/^reporting=1/reporting=0/' "$config"
  grep -q '^reporting=0' "$config" || echo 'reporting=0' >> "$config"
fi

# Legacy opt-out files. unified_analytics treats any of them as an opt-out.
# They hold no client ID.
echo '{"firstRun": false, "enabled": false}' > "$HOME/.flutter"
echo '{"firstRun": false, "enabled": false, "disclosureShown": true}' > "$HOME/.dart/dartdev.json"
echo '{"analyticsEnabled": false, "isFirstRun": false}' > "$HOME/.flutter-devtools/.devtools"

# 3. Suppression variables in shell profiles, as well as in the dev container's
#    containerEnv, so terminals opened any other way (DevPod SSH, `docker exec`)
#    get them too. The PATH line makes the pinned Flutter available.
for profile in "$HOME/.bashrc" "$HOME/.profile"; do
  touch "$profile"
  if ! grep -q 'portfolio-jockey telemetry lockdown' "$profile"; then
    cat >> "$profile" <<'EOF'

# portfolio-jockey telemetry lockdown (see .devcontainer/lockdown.sh)
export FLUTTER_SUPPRESS_ANALYTICS=true
export DASH__SUPPRESS_ANALYTICS=true
export DO_NOT_TRACK=1
case ":$PATH:" in *":$HOME/flutter/bin:"*) ;; *) export PATH="$PATH:$HOME/flutter/bin" ;; esac
EOF
  fi
done

echo "Telemetry lockdown applied."

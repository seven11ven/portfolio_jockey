#!/usr/bin/env bash
# Portfolio Jockey: verify that Flutter, Dart and editor telemetry are blocked.
# Exits non-zero, and names every problem, if any layer is missing.
# Runs on every container start, after lockdown.sh. Run it by hand any time:
#   bash .devcontainer/check-lockdown.sh
set -uo pipefail

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
pass() { echo "ok:   $*"; }

# Layer 1: telemetry hosts resolve to nowhere (IPv4 and IPv6).
for host in www.google-analytics.com ssl.google-analytics.com region1.google-analytics.com analytics.google.com clients2.google.com; do
  addrs=$(getent ahosts "$host" | awk '{print $1}' | sort -u | tr '\n' ' ')
  bad=$(echo "$addrs" | tr ' ' '\n' | grep -vE '^(0\.0\.0\.0|::)?$' || true)
  if [ -z "$addrs" ] || [ -n "$bad" ]; then
    fail "$host resolves to '${addrs}' (expected only 0.0.0.0 / ::)"
  else
    pass "$host blocked"
  fi
done

# Layer 2: opt-out config written, never enabled.
config="$HOME/.dart-tool/dart-flutter-telemetry.config"
if [ -f "$config" ] && grep -q '^reporting=0' "$config" && ! grep -q '^reporting=1' "$config"; then
  pass "dart-flutter-telemetry.config says reporting=0"
else
  fail "$config missing or not set to reporting=0"
fi
grep -q '"enabled": false' "$HOME/.flutter" 2>/dev/null && pass "legacy ~/.flutter opted out" || fail "legacy ~/.flutter not opted out"
grep -q '"enabled": false' "$HOME/.dart/dartdev.json" 2>/dev/null && pass "legacy ~/.dart/dartdev.json opted out" || fail "legacy ~/.dart/dartdev.json not opted out"
grep -q '"analyticsEnabled": false' "$HOME/.flutter-devtools/.devtools" 2>/dev/null && pass "legacy DevTools settings opted out" || fail "legacy DevTools settings not opted out"

# Layer 2: suppression variables set in this environment.
[ "${FLUTTER_SUPPRESS_ANALYTICS:-}" = "true" ] && pass "FLUTTER_SUPPRESS_ANALYTICS=true" || fail "FLUTTER_SUPPRESS_ANALYTICS is not true"
[ "${DASH__SUPPRESS_ANALYTICS:-}" = "true" ] && pass "DASH__SUPPRESS_ANALYTICS=true" || fail "DASH__SUPPRESS_ANALYTICS is not true"
[ "${DO_NOT_TRACK:-}" = "1" ] && pass "DO_NOT_TRACK=1" || fail "DO_NOT_TRACK is not 1"

# Layer 5: telemetry removed from the Flutter tool's source (once Flutter is installed).
patch_file="$(cd "$(dirname "$0")" && pwd)/flutter-remove-telemetry.patch"
if [ -d "$HOME/flutter/.git" ]; then
  if git -C "$HOME/flutter" apply --reverse --check "$patch_file" 2>/dev/null; then
    pass "Flutter tool telemetry patch applied"
  else
    fail "Flutter tool telemetry patch is NOT applied (run .devcontainer/setup.sh)"
  fi
  # Upgrading or switching channels would replace the patched source.
  if [ -n "$(git -C "$HOME/flutter" status --porcelain -- packages/flutter_tools/lib/src/reporting | grep -v '^ M')" ]; then
    fail "unexpected changes in Flutter's reporting code"
  fi
else
  echo "skip: Flutter not installed yet, patch check skipped"
fi

# Evidence: nothing was ever recorded for sending.
log="$HOME/.dart-tool/dart-flutter-telemetry.log"
if [ ! -s "$log" ]; then pass "telemetry log empty or absent"; else fail "$log has $(wc -l < "$log") recorded events"; fi
clientid="$HOME/.dart-tool/CLIENT_ID"
if [ ! -s "$clientid" ]; then pass "no telemetry client ID"; else fail "$clientid holds a client ID"; fi

if [ "$failures" -gt 0 ]; then
  echo "Telemetry lockdown check FAILED ($failures problem(s)). Don't run Flutter or Dart until fixed."
  exit 1
fi
echo "Telemetry lockdown check passed."

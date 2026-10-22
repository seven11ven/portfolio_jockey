#!/usr/bin/env bash
# Portfolio Jockey: verify the app has no network, analytics, tracking or
# crash-reporting code, in its own source or in any package it depends on.
# Exits non-zero, and names every problem, if anything is found.
# Run it after every `flutter pub get` and before every commit:
#   bash app/tool/check-privacy.sh
#
# Checks:
#   1. Every package in pubspec.lock is listed, at that exact version, in
#      tool/allowed-packages.txt. Only pub.dev and Flutter SDK packages are allowed,
#      plus empty stand-ins in tool/stubs/ (pubspec and README only, no code).
#   2. No package name matches a known network, analytics or crash-reporting package.
#   3. The app's own Dart code (lib/, test/) uses no network APIs.
#   4. The Linux runner (linux/) uses no network libraries.
#   5. Every package's compiled code (lib/), build hooks (hook/) and plugin native
#      code (linux/) are scanned for network and telemetry patterns. Each hit must be listed, for that exact
#      package version, in tool/reviewed-hits.txt. A new version means a new review.
#   6. Native code: only the files listed in tool/allowed-native-libs.txt may
#      load native libraries, only the libraries listed for them, and only the
#      listed symbols (so libc's socket functions, say, can't be reached).
#
# `--list-hits` prints the current check-5 hits in reviewed-hits.txt format,
# to help with a review. Never paste them in without reading the code.
set -uo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
lock="$app_dir/pubspec.lock"
allowed="$app_dir/tool/allowed-packages.txt"
reviewed="$app_dir/tool/reviewed-hits.txt"
pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
flutter_root="${FLUTTER_ROOT:-$HOME/flutter}"

list_only=0
[ "${1:-}" = "--list-hits" ] && list_only=1

failures=0
fail() { [ "$list_only" -eq 1 ] || echo "FAIL: $*"; failures=$((failures + 1)); }
pass() { [ "$list_only" -eq 1 ] || echo "ok:   $*"; }

# Network APIs, in Dart. Comment lines are skipped before matching.
net_re='\b(HttpClient|HttpServer|HttpRequest|RawSocket|ServerSocket|SecureSocket|SecureServerSocket|RawDatagramSocket|WebSocket|Socket|InternetAddress|NetworkInterface|NetworkImage|NetworkAssetBundle|XMLHttpRequest|sendBeacon|vmServiceConnectUri|controlWebServer)\b|Image\.network|dart:html|package:http/|package:web_socket|package:grpc|\bfetch\('
# Telemetry, tracking and crash-reporting markers (case-insensitive).
tel_re='google-analytics|googletagmanager|analytics|telemetry|crashlytics|crash.?report|measurement_?id|segment\.(io|com)|\b(sentry|firebase|amplitude|mixpanel|posthog|datadog|bugsnag|appcenter|newrelic|instabug|rollbar|countly|matomo)\b'
# Network use in native (C/C++) code: plugins' linux/ folders and the Linux runner.
native_net_re='curl|soup|socket|getaddrinfo|gethostbyname|GResolver|g_network|GNetwork|FetchContent|ExternalProject|https?://'
# Test-only switches that start the Dart VM's local debug server (see leak_tracker in docs/dependencies.md).
vm_re='collectRetainingPathForNotGCed|formattedRetainingPath|retainingPathCollector'
# Known network, analytics and crash-reporting packages, by name.
block_re='^(http|http2|http_parser|dio|dio_.*|chopper|retrofit|graphql.*|grpc|web_socket.*|socket_io.*|.*_http|.*_http_.*|connectivity.*|network_info.*|firebase.*|cloud_.*|supabase.*|appwrite|amplify.*|aws_.*|google_sign_in.*|.*analytics.*|.*crashlytics.*|.*telemetry.*|sentry.*|bugsnag.*|datadog.*|amplitude.*|mixpanel.*|posthog.*|segment.*|appcenter.*|newrelic.*|instabug.*|rollbar.*|countly.*|matomo.*|onesignal.*|google_mobile_ads|.*_ads)$'

# Drop Dart, C++ and CMake comment lines from grep -n output ("file:line:text").
# CMake comments are "# ..." or a bare "#", so C++ "#include" lines are still scanned.
strip_comments() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/?\*|#([[:space:]]|$))'; }

[ -f "$lock" ] || { echo "FAIL: $lock not found. Run 'flutter pub get' in app/ first."; exit 1; }

# name version source url
packages=$(awk '
  /^packages:/ { p = 1; next }
  /^[^ ]/      { p = 0 }
  p && /^  [a-z0-9_]+:$/ { name = substr($1, 1, length($1) - 1); url = "-" }
  p && /^ +(url|path):/ { url = $2; gsub(/"/, "", url) }
  p && /^ +source:/  { src = $2 }
  p && /^ +version:/ { v = $2; gsub(/"/, "", v); print name, v, src, url }
' "$lock")

flutter_version=$(grep -o '"frameworkVersion": *"[^"]*"' "$flutter_root/bin/cache/flutter.version.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$flutter_version" ] || { echo "FAIL: can't read the Flutter version under $flutter_root"; exit 1; }

# Prints "id dir" for a package. SDK packages are identified by the Flutter version.
locate() {
  local name=$1 version=$2 src=$3
  if [ "$src" = hosted ]; then
    echo "$name@$version $pub_cache/hosted/pub.dev/$name-$version"
  elif [ "$name" = sky_engine ]; then
    echo "$name@flutter-$flutter_version $flutter_root/bin/cache/pkg/sky_engine"
  else
    echo "$name@flutter-$flutter_version $flutter_root/packages/$name"
  fi
}

# True if [name] at lock path [path] is an empty stand-in: it lives in
# tool/stubs/<name>/, holds only pubspec.yaml and README.md (plus the
# pubspec.lock and .dart_tool/package_config files pub generates), contains no
# code anywhere, and declares no dependencies.
is_stub() {
  local name=$1 path=$2 dir="$app_dir/tool/stubs/$1"
  [ "$path" = "tool/stubs/$name" ] && [ -d "$dir" ] || return 1
  local extra
  extra=$(find "$dir" -mindepth 1 \
    ! -path "$dir/pubspec.yaml" ! -path "$dir/README.md" ! -path "$dir/pubspec.lock" \
    ! -path "$dir/.dart_tool" ! -path "$dir/.dart_tool/package_config.json" \
    ! -path "$dir/.dart_tool/package_graph.json" ! -path "$dir/.dart_tool/version")
  [ -z "$extra" ] || return 1
  ! grep -qE '^(dependencies|dev_dependencies|dependency_overrides):' "$dir/pubspec.yaml"
}

# Prints "id<TAB>file<TAB>token" for every pattern hit in one package.
package_hits() {
  local id=$1 dir=$2 scan=()
  [ -d "$dir/lib" ] && scan+=("$dir/lib")
  [ -d "$dir/hook" ] && { scan+=("$dir/hook"); printf '%s\t%s\t%s\n' "$id" "hook/" "build-hook"; }
  {
    if [ ${#scan[@]} -gt 0 ]; then
      grep -rnE --include='*.dart' "$net_re" "${scan[@]}" | strip_comments | while IFS= read -r line; do
        grep -oE "$net_re" <<<"${line#*:*:}" | sed "s|^|${line%%:*}\t|"
      done
      grep -rniE --include='*.dart' "$tel_re" "${scan[@]}" | strip_comments | while IFS= read -r line; do
        grep -oiE "$tel_re" <<<"${line#*:*:}" | tr 'A-Z' 'a-z' | sed "s|^|${line%%:*}\t|"
      done
    fi
    # Plugins compile their linux/ C/C++ code into the app.
    if [ -d "$dir/linux" ]; then
      grep -rnEi --include='*.c' --include='*.cc' --include='*.cpp' --include='*.h' --include='CMakeLists.txt' \
        "$native_net_re|$tel_re" "$dir/linux" | strip_comments | while IFS= read -r line; do
        grep -oiE "$native_net_re|$tel_re" <<<"${line#*:*:}" | tr 'A-Z' 'a-z' | sed "s|^|${line%%:*}\t|"
      done
    fi
  } | sed "s|^$dir/||" | sort -u | sed "s|^|$id\t|"
}

# 1 and 2: allowlist, sources and blocklist.
while read -r name version src url; do
  [ -n "$name" ] || continue
  if [ "$src" = path ]; then
    # Only the empty stand-ins in tool/stubs/ (see tool/stubs/http/README.md).
    if is_stub "$name" "$url"; then
      pass "$name is the empty stand-in in $url"
    else
      fail "$name comes from the local path $url; only empty stand-ins in tool/stubs/ are allowed"
    fi
    continue
  elif [ "$src" = hosted ] && [ "$url" != "https://pub.dev" ]; then
    fail "$name comes from $url, not pub.dev"
  elif [ "$src" != hosted ] && [ "$src" != sdk ]; then
    fail "$name comes from a '$src' source; only pub.dev and the Flutter SDK are allowed"
  fi
  # Exact field match: versions like 0.9.4+1 contain regex characters.
  if awk -v n="$name" -v v="$version" '$1 == n && $2 == v { found = 1 } END { exit !found }' "$allowed"; then
    pass "$name $version is allowlisted"
  else
    fail "$name $version is not in tool/allowed-packages.txt (vet it and record it in docs/dependencies.md first)"
  fi
  if grep -qE "$block_re" <<<"$name"; then
    fail "$name is a known network, analytics or crash-reporting package"
  fi
done <<<"$packages"

# 3: the app's own Dart code.
app_src=()
for d in lib test bin; do [ -d "$app_dir/$d" ] && app_src+=("$app_dir/$d"); done
hits=$(grep -rnE --include='*.dart' "$net_re|$vm_re" "${app_src[@]}" | strip_comments)
hits+=$(grep -rniE --include='*.dart' "$tel_re" "${app_src[@]}" | strip_comments)
if [ -z "$hits" ]; then pass "app code uses no network, telemetry or VM-service APIs"; else
  fail "app code uses network, telemetry or VM-service APIs:"; [ "$list_only" -eq 1 ] || sed "s|^$app_dir/|      |" <<<"$hits"; fi

# 4: the Linux runner.
hits=$(grep -rnEi "$native_net_re" "$app_dir/linux" \
  --exclude-dir=ephemeral | strip_comments)
if [ -z "$hits" ]; then pass "Linux runner uses no network libraries"; else
  fail "Linux runner references network code:"; [ "$list_only" -eq 1 ] || sed "s|^$app_dir/|      |" <<<"$hits"; fi

# 6: native libraries and symbols.
native_allowed="$app_dir/tool/allowed-native-libs.txt"
native_problems=0
hits=$(grep -rnE --include='*.dart' 'DynamicLibrary\.(process|executable)|@(ffi\.)?Native\b' "$app_dir/lib" | strip_comments)
if [ -n "$hits" ]; then
  fail "app code looks up native symbols without naming a library:"; [ "$list_only" -eq 1 ] || sed "s|^$app_dir/|      |" <<<"$hits"
  native_problems=$((native_problems + 1))
fi
while IFS= read -r file; do
  rel=${file#"$app_dir/"}
  code=$(grep -HnE '' "$file" | strip_comments | cut -d: -f3-)
  entry=$(grep -vE '^[[:space:]]*(#|$)' "$native_allowed" 2>/dev/null | awk -v f="$rel" '$1 == f { print $2, $3 }')
  if [ -z "$entry" ]; then
    fail "$rel loads native code but isn't listed in tool/allowed-native-libs.txt"
    native_problems=$((native_problems + 1))
    continue
  fi
  read -r libs symbols <<<"$entry"
  opens=$(grep -oE 'DynamicLibrary\.open\(' <<<"$code" | wc -l)
  named=$(grep -oE "DynamicLibrary\.open\('[^']+'\)" <<<"$code" | sed -E "s/.*\('([^']+)'\)/\1/")
  if [ "$opens" -ne "$(grep -c . <<<"$named")" ]; then
    fail "$rel opens a native library whose name isn't a plain string, so it can't be checked"
    native_problems=$((native_problems + 1))
  fi
  for lib in $named; do
    if ! tr ',' '\n' <<<"$libs" | grep -qxF "$lib"; then
      fail "$rel opens $lib, which isn't allowed for it"
      native_problems=$((native_problems + 1))
    fi
  done
  lookups=$(grep -oE 'lookupFunction<|\.lookup<' <<<"$code" | wc -l)
  looked_up=$(grep -oE ">\('[A-Za-z0-9_]+'\)" <<<"$code" | sed -E "s/>\('([^']+)'\)/\1/")
  if [ "$lookups" -ne "$(grep -c . <<<"$looked_up")" ]; then
    fail "$rel looks up a native symbol whose name isn't a plain string, so it can't be checked"
    native_problems=$((native_problems + 1))
  fi
  if [ "$symbols" != "*" ]; then
    for symbol in $looked_up; do
      if ! tr ',' '\n' <<<"$symbols" | grep -qxF "$symbol"; then
        fail "$rel looks up '$symbol', which isn't allowed for it"
        native_problems=$((native_problems + 1))
      fi
    done
  fi
done < <(grep -rlE --include='*.dart' 'DynamicLibrary\.open|lookupFunction<|\.lookup<' "$app_dir/lib" | sort)
[ "$native_problems" -eq 0 ] && pass "native code loads only allowlisted libraries and symbols"

# 5: dependency code scan.
all_hits=""
while read -r name version src url; do
  [ -n "$name" ] || continue
  # Empty stand-ins hold no code; check 1 verified that.
  [ "$src" = path ] && continue
  read -r id dir <<<"$(locate "$name" "$version" "$src")"
  if [ ! -d "$dir" ]; then fail "source of $id not found at $dir (run 'flutter pub get')"; continue; fi
  # The Dart standard library defines dart:io's HttpClient and friends. Defining
  # them isn't using them, and check 3 catches the app using them.
  [ "$name" = sky_engine ] && continue
  all_hits+=$(package_hits "$id" "$dir")$'\n'
done <<<"$packages"
all_hits=$(sed '/^$/d' <<<"$all_hits")

if [ "$list_only" -eq 1 ]; then
  echo "$all_hits"
  exit 0
fi

unreviewed=0
while IFS=$'\t' read -r id file token; do
  [ -n "$id" ] || continue
  if ! grep -qF "$(printf '%s\t%s\t%s\t' "$id" "$file" "$token")" "$reviewed"; then
    fail "unreviewed '$token' in $id: $file"
    unreviewed=$((unreviewed + 1))
  fi
done <<<"$all_hits"
[ "$unreviewed" -eq 0 ] && pass "all $(grep -c . <<<"$all_hits") dependency code hits are reviewed for these exact versions"

if [ "$failures" -gt 0 ]; then
  echo "Privacy check FAILED ($failures problem(s))."
  exit 1
fi
echo "Privacy check passed."

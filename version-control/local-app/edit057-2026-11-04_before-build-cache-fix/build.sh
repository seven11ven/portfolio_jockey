#!/usr/bin/env bash
# Builds the Debian package from a clean Flutter release build.
#
# Usage (from a clean, committed worktree on Debian 12 amd64):
#   bash packaging/debian/build.sh
#
# The version, Debian revision and maintainer come from the top entry of
# packaging/debian/changelog. Add a new entry there for every package release:
# the revision starts at 1 for each app version and goes up when only the
# packaging changes.
set -euo pipefail
umask 022

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
packaging="$repo/packaging/debian"
app="$repo/app"
app_id=io.github.seven11ven.portfolio_jockey
bundle="$app/build/linux/x64/release/bundle"
output_dir="$repo/project-builds/release-builds"
logs_dir="$repo/project-builds/logs"
changelog_src="$packaging/changelog"

if [[ $# -ne 0 ]]; then
	echo "Usage: bash packaging/debian/build.sh" >&2
	echo "The version and maintainer come from packaging/debian/changelog." >&2
	exit 2
fi

for tool in dpkg dpkg-deb dpkg-shlibdeps dpkg-parsechangelog desktop-file-validate lintian \
	gzip patchelf strip md5sum git flutter; do
	command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

if [[ "$(dpkg --print-architecture)" != amd64 ]]; then
	echo "Debian packages are currently supported only on amd64." >&2
	exit 1
fi

if [[ ! -r /etc/debian_version ]] || ! grep -q '^12' /etc/debian_version; then
	echo "Build on Debian 12 to preserve the supported glibc baseline." >&2
	exit 1
fi

if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
	echo "Refusing to package a dirty worktree. Commit the reviewed source first." >&2
	exit 1
fi
commit=$(git -C "$repo" rev-parse HEAD)

app_version=$(sed -nE "s/^const String appVersion = '([^']+)';/\1/p" "$app/lib/app/version.dart")
package_version=$(dpkg-parsechangelog -l "$changelog_src" -S Version)
maintainer=$(dpkg-parsechangelog -l "$changelog_src" -S Maintainer)
if [[ -z "$app_version" || "${package_version%-*}" != "$app_version" ]]; then
	echo "The top entry of packaging/debian/changelog ($package_version) does not match" >&2
	echo "appVersion ($app_version). Add a changelog entry for this version first." >&2
	exit 1
fi
if [[ ! "$package_version" =~ ^[0-9][0-9A-Za-z.+~]*-[1-9][0-9]*$ ]]; then
	echo "Package version $package_version must be <app version>-<revision>." >&2
	exit 1
fi
if [[ -z "$maintainer" || "$maintainer" == *$'\n'* || "$maintainer" != *'<'*'@'*'>' ]]; then
	echo "The changelog's maintainer must be 'Name <email>'." >&2
	exit 1
fi

output="$output_dir/portfolio-jockey_${package_version}_amd64.deb"
summary="$logs_dir/portfolio-jockey_${package_version}_amd64.md"
if [[ -e "$output" || -e "$summary" ]]; then
	echo "Refusing to overwrite an existing package or build summary." >&2
	exit 1
fi

echo "== Checks"
bash "$repo/.devcontainer/check-lockdown.sh"
(
	cd "$app"
	bash tool/check-privacy.sh
	flutter analyze --fatal-infos --fatal-warnings
	flutter test
)

echo "== Clean release build"
# Remove every earlier build so no leftover files reach the package. Keeps
# .dart_tool, so no package download is needed. Keep every icon, as in
# app/tool/package-bundle.sh.
rm -rf "$app/build"
(cd "$app" && flutter build linux --release --no-tree-shake-icons)
if [[ ! -x "$bundle/portfolio_jockey" || ! -f "$bundle/data/flutter_assets/AssetManifest.bin" ]]; then
	echo "The release build did not produce a complete bundle at $bundle" >&2
	exit 1
fi
if [[ -n "$(git -C "$repo" status --porcelain)" || "$(git -C "$repo" rev-parse HEAD)" != "$commit" ]]; then
	echo "The worktree changed during the build; refusing to package it." >&2
	exit 1
fi

echo "== Package"
work=$(mktemp -d "${TMPDIR:-/tmp}/portfolio-jockey-deb.XXXXXX")
trap 'rm -rf "$work"' EXIT
root="$work/root"
mkdir -p \
	"$root/DEBIAN" \
	"$root/usr/lib/portfolio-jockey" \
	"$root/usr/bin" \
	"$root/usr/share/applications" \
	"$root/usr/share/icons/hicolor/scalable/apps" \
	"$root/usr/share/doc/portfolio-jockey" \
	"$root/usr/share/lintian/overrides" \
	"$root/usr/share/man/man1" \
	"$work/debian"
cp -a "$bundle/." "$root/usr/lib/portfolio-jockey/"
ln -s ../lib/portfolio-jockey/portfolio_jockey "$root/usr/bin/portfolio-jockey"
install -m 0644 "$packaging/$app_id.desktop" "$root/usr/share/applications/$app_id.desktop"
install -m 0644 "$repo/packaging/flatpak/$app_id.svg" \
	"$root/usr/share/icons/hicolor/scalable/apps/$app_id.svg"
install -m 0644 "$repo/LICENSE" "$root/usr/share/doc/portfolio-jockey/copyright"
gzip -n -9 -c "$packaging/portfolio-jockey.1" > "$root/usr/share/man/man1/portfolio-jockey.1.gz"
chmod 0644 "$root/usr/share/man/man1/portfolio-jockey.1.gz"
install -m 0644 "$packaging/portfolio-jockey.lintian-overrides" \
	"$root/usr/share/lintian/overrides/portfolio-jockey"
gzip -n -9 -c "$changelog_src" > "$root/usr/share/doc/portfolio-jockey/changelog.Debian.gz"
chmod 0644 "$root/usr/share/doc/portfolio-jockey/changelog.Debian.gz"

strip --strip-unneeded "$root/usr/lib/portfolio-jockey/portfolio_jockey"
while IFS= read -r -d '' object; do
	strip --strip-unneeded "$object"
done < <(find "$root/usr/lib/portfolio-jockey/lib" -type f -name '*.so*' -print0)
patchelf --set-rpath '$ORIGIN' \
	"$root/usr/lib/portfolio-jockey/lib/libfile_selector_linux_plugin.so"

cat > "$work/debian/control" <<EOF
Source: portfolio-jockey
Section: utils
Priority: optional
Maintainer: $maintainer
Standards-Version: 4.6.2

Package: portfolio-jockey
Architecture: amd64
Description: Local encrypted project tracker
 Portfolio Jockey keeps project files encrypted in a local vault.
EOF

elf_args=(-e "$root/usr/lib/portfolio-jockey/portfolio_jockey")
while IFS= read -r -d '' object; do
	elf_args+=(-e "$object")
done < <(find "$root/usr/lib/portfolio-jockey/lib" -type f -name '*.so*' -print0)
shlibs=$(cd "$work" && dpkg-shlibdeps -O -S"$root" -l"$root/usr/lib/portfolio-jockey/lib" \
	"${elf_args[@]}")
shlibs_depends=${shlibs#shlibs:Depends=}
if [[ "$shlibs_depends" == "$shlibs" || -z "$shlibs_depends" ]]; then
	echo "dpkg-shlibdeps did not produce runtime dependencies." >&2
	exit 1
fi

# Every package dpkg-shlibdeps may return, reviewed on 2026-11-04 against
# packages.debian.org (bookworm, trixie) and packages.ubuntu.com (jammy, noble).
# A new name stops the build so it gets the same review first.
reviewed=" libatk1.0-0 libc6 libcairo-gobject2 libcairo2 libepoxy0 libfontconfig1 libgcc-s1 \
libgdk-pixbuf-2.0-0 libglib2.0-0 libgtk-3-0 libharfbuzz0b libpango-1.0-0 libpangocairo-1.0-0 \
libstdc++6 zlib1g "
# Renamed with a t64 suffix in Debian 13 and Ubuntu 24.04 (64-bit time_t
# transition). The new packages don't Provide the old names, so the package
# lists both: "<name>t64 | <name>".
t64_renamed=" libatk1.0-0 libglib2.0-0 libgtk-3-0 "
depends=()
IFS=',' read -ra entries <<< "$shlibs_depends"
for entry in "${entries[@]}"; do
	entry="${entry#"${entry%%[![:space:]]*}"}"
	entry="${entry%"${entry##*[![:space:]]}"}"
	name=${entry%% *}
	if [[ "$entry" == *'|'* || "$reviewed" != *" $name "* ]]; then
		echo "dpkg-shlibdeps returned '$entry', which is not in the reviewed list." >&2
		echo "Check its name on Debian 12/13 and Ubuntu 22.04/24.04, then add it to build.sh." >&2
		exit 1
	fi
	if [[ "$t64_renamed" == *" $name "* ]]; then
		depends+=("${name}t64${entry#"$name"} | $entry")
	else
		depends+=("$entry")
	fi
done
# Loaded at run time through dart:ffi, so dpkg-shlibdeps can't see them. The
# app opens libsodium.so.26 or libsodium.so.23, and libpoppler-glib.so.8.
depends+=("libpoppler-glib8t64 | libpoppler-glib8" "libsodium23 | libsodium26")
depends_field=$(printf '%s, ' "${depends[@]}")
depends_field=${depends_field%, }

find "$root" -type d -exec chmod 0755 {} +
installed_size=$(du -sk --apparent-size "$root/usr" | cut -f1)

cat > "$root/DEBIAN/control" <<EOF
Package: portfolio-jockey
Version: $package_version
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $installed_size
Maintainer: $maintainer
Depends: $depends_field
Description: Local encrypted project tracker
 Portfolio Jockey keeps project files encrypted in a local vault.
 Projects, tags and files stay on this device, encrypted with libsodium,
 and the app never uses the network.
EOF
(cd "$root" && find usr -type f -print0 | sort -z | xargs -0 md5sum) > "$root/DEBIAN/md5sums"
chmod 0644 "$root/DEBIAN/control" "$root/DEBIAN/md5sums"

mkdir -p "$output_dir" "$logs_dir"
bash "$packaging/check.sh" --staged "$root"
candidate="$work/portfolio-jockey_${package_version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$candidate"
bash "$packaging/check.sh" --package "$candidate"
lint_status=0
lintian --show-overrides "$candidate" > "$work/lintian.log" 2>&1 || lint_status=$?
cat "$work/lintian.log"
override_count=$(grep -c '^O: portfolio-jockey: embedded-library ' "$work/lintian.log" || true)
total_override_count=$(grep -c '^O:' "$work/lintian.log" || true)
has_unapproved_errors=0
grep -q '^E:' "$work/lintian.log" && has_unapproved_errors=1 || true
if [[ ( "$lint_status" -ne 0 && "$lint_status" -ne 2 ) ||
	"$has_unapproved_errors" -ne 0 ||
	"$override_count" -ne 2 ||
	"$total_override_count" -ne 2 ]]; then
	echo "Lintian found an unapproved error or override; refusing to publish the package." >&2
	exit 1
fi
mv -- "$candidate" "$output"

{
	printf '# Debian Build Summary\n\n'
	printf '**Built:** %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
	printf '**Package:** portfolio-jockey\n'
	printf '**Version:** %s\n' "$package_version"
	printf '**Architecture:** amd64\n'
	printf '**Source commit:** %s\n' "$commit"
	printf '**Source bundle:** clean Flutter Linux release build\n'
	printf '**SHA-256:** %s\n' "$(sha256sum "$output" | cut -d' ' -f1)"
	printf '**Depends:** %s\n' "$(dpkg-deb -f "$output" Depends)"
	printf '**Verification:** checks, tests and package checks passed; lintian reported the two documented Flutter-engine overrides and any warnings shown in the build output\n'
	printf '**Not yet verified:** clean install and launch on Debian 12/13 and Ubuntu 22.04/24.04\n'
} > "$summary"

printf 'Built and checked: %s\nBuild summary: %s\n' "$output" "$summary"

#!/usr/bin/env bash
set -euo pipefail
umask 022

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
packaging="$repo/packaging/debian"
app="$repo/app"
app_id=io.github.seven11ven.portfolio_jockey
bundle="$app/build/linux/x64/release/bundle"
output_dir="$repo/project-builds/release-builds"
logs_dir="$repo/project-builds/logs"
version=$(sed -nE "s/^const String appVersion = '([^']+)';/\1/p" "$app/lib/app/version.dart")
maintainer=${1:-}

if [[ -z "$maintainer" || "$maintainer" == *$'\n'* ]]; then
	echo "Usage: bash packaging/debian/build.sh 'Name <email>'" >&2
	exit 2
fi

for tool in dpkg dpkg-deb dpkg-shlibdeps desktop-file-validate lintian gzip patchelf; do
	command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
command -v strip >/dev/null || { echo "Missing required tool: strip" >&2; exit 1; }

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

if [[ -z "$version" || ! -x "$bundle/portfolio_jockey" || ! -f "$bundle/data/flutter_assets/AssetManifest.bin" ]]; then
	echo "A complete Flutter release bundle is required at $bundle" >&2
	exit 1
fi

package_version="${version}-1"
output="$output_dir/portfolio-jockey_${package_version}_amd64.deb"
summary="$logs_dir/portfolio-jockey_${package_version}_amd64.md"
if [[ -e "$output" || -e "$summary" ]]; then
	echo "Refusing to overwrite an existing package or build summary." >&2
	exit 1
fi

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
ln -s /usr/lib/portfolio-jockey/portfolio_jockey "$root/usr/bin/portfolio-jockey"
install -m 0644 "$packaging/$app_id.desktop" "$root/usr/share/applications/$app_id.desktop"
install -m 0644 "$repo/packaging/flatpak/$app_id.svg" \
	"$root/usr/share/icons/hicolor/scalable/apps/$app_id.svg"
install -m 0644 "$repo/LICENSE" "$root/usr/share/doc/portfolio-jockey/copyright"
gzip -n -9 -c "$packaging/portfolio-jockey.1" > "$root/usr/share/man/man1/portfolio-jockey.1.gz"
chmod 0644 "$root/usr/share/man/man1/portfolio-jockey.1.gz"
install -m 0644 "$packaging/portfolio-jockey.lintian-overrides" \
	"$root/usr/share/lintian/overrides/portfolio-jockey"
chmod 0644 "$root/usr/share/man/man1/portfolio-jockey.1.gz"

printf 'portfolio-jockey (%s) unstable; urgency=medium\n\n  * Initial Debian packaging.\n\n -- %s  %s\n' \
	"$package_version" "$maintainer" "$(date -R)" > "$work/changelog"
gzip -n -9 -c "$work/changelog" > "$root/usr/share/doc/portfolio-jockey/changelog.Debian.gz"
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

cat > "$root/DEBIAN/control" <<EOF
Package: portfolio-jockey
Version: $package_version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: $maintainer
Depends: $shlibs_depends, libpoppler-glib8, libsodium23
Description: Local encrypted project tracker
 Portfolio Jockey keeps project files encrypted in a local vault.
EOF

find "$root" -type d -exec chmod 0755 {} +
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
	printf '**Source bundle:** Flutter Linux release bundle\n'
	printf '**Depends:** %s\n' "$(dpkg-deb -f "$output" Depends)"
	printf '**Verification:** package checks passed; lintian reported two documented Flutter-engine overrides and any visible warnings\n'
} > "$summary"

printf 'Built and checked: %s\nBuild summary: %s\n' "$output" "$summary"
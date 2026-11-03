#!/usr/bin/env bash
set -euo pipefail
umask 022

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
packaging="$repo/packaging/debian"
app="$repo/app"
bundle="$app/build/linux/x64/release/bundle"
output_dir="$repo/project-builds/release-builds"
logs_dir="$repo/project-builds/logs"
version=$(sed -nE "s/^const String appVersion = '([^']+)';/\1/p" "$app/lib/app/version.dart")
maintainer=${1:-}

if [[ -z "$maintainer" || "$maintainer" == *$'\n'* ]]; then
	echo "Usage: bash packaging/debian/build.sh 'Name <email>'" >&2
	exit 2
fi

for tool in dpkg dpkg-deb dpkg-shlibdeps desktop-file-validate lintian; do
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
	"$root/opt/portfolio-jockey" \
	"$root/usr/bin" \
	"$root/usr/share/applications" \
	"$root/usr/share/icons/hicolor/scalable/apps" \
	"$root/usr/share/licenses/portfolio-jockey" \
	"$work/debian"
cp -a "$bundle/." "$root/opt/portfolio-jockey/"
ln -s ../../opt/portfolio-jockey/portfolio_jockey "$root/usr/bin/portfolio-jockey"
install -m 0644 "$packaging/portfolio-jockey.desktop" "$root/usr/share/applications/portfolio-jockey.desktop"
install -m 0644 "$repo/packaging/flatpak/io.github.seven11ven.portfolio_jockey.svg" \
	"$root/usr/share/icons/hicolor/scalable/apps/io.github.seven11ven.portfolio_jockey.svg"
install -m 0644 "$repo/LICENSE" "$root/usr/share/licenses/portfolio-jockey/LICENSE"

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

shlibs=$(cd "$work" && dpkg-shlibdeps -O -S"$root" -l"$root/opt/portfolio-jockey/lib" \
	-e "$root/opt/portfolio-jockey/portfolio_jockey")
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
bash "$packaging/check.sh" "$candidate"
lintian "$candidate"
mv -- "$candidate" "$output"

{
	printf '# Debian Build Summary\n\n'
	printf '**Built:** %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
	printf '**Package:** portfolio-jockey\n'
	printf '**Version:** %s\n' "$package_version"
	printf '**Architecture:** amd64\n'
	printf '**Source bundle:** Flutter Linux release bundle\n'
	printf '**Depends:** %s\n' "$(dpkg-deb -f "$output" Depends)"
	printf '**Verification:** staged and extracted package checks passed; lintian passed\n'
} > "$summary"

printf 'Built and checked: %s\nBuild summary: %s\n' "$output" "$summary"
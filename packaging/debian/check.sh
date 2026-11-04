#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
packaging="$repo/packaging/debian"
app_id=io.github.seven11ven.portfolio_jockey
mode=${1:-}
target=${2:-}

if [[ "$mode" != --staged && "$mode" != --package ]]; then
	echo "Usage: bash packaging/debian/check.sh --staged <root> | --package <file.deb>" >&2
	exit 2
fi
if [[ -z "$target" ]]; then
	echo "A staging root or package path is required." >&2
	exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/portfolio-jockey-deb-check.XXXXXX")
trap 'rm -rf "$work"' EXIT
root="$target"
if [[ "$mode" == --package ]]; then
	dpkg-deb -f "$target" Package Version Architecture Depends
	root="$work/root"
	dpkg-deb -x "$target" "$root"
fi

binary="$root/usr/lib/portfolio-jockey/portfolio_jockey"
desktop="$root/usr/share/applications/$app_id.desktop"
icon="$root/usr/share/icons/hicolor/scalable/apps/$app_id.svg"
copyright="$root/usr/share/doc/portfolio-jockey/copyright"
changelog="$root/usr/share/doc/portfolio-jockey/changelog.Debian.gz"
manpage="$root/usr/share/man/man1/portfolio-jockey.1.gz"
overrides="$root/usr/share/lintian/overrides/portfolio-jockey"
link="$root/usr/bin/portfolio-jockey"

for path in \
	"$binary" \
	"$root/usr/lib/portfolio-jockey/data/flutter_assets/AssetManifest.bin" \
	"$root/usr/lib/portfolio-jockey/lib/libapp.so" \
	"$root/usr/lib/portfolio-jockey/lib/libfile_selector_linux_plugin.so" \
	"$root/usr/lib/portfolio-jockey/lib/libflutter_linux_gtk.so" \
	"$desktop" \
	"$icon" \
	"$copyright" \
	"$changelog" \
	"$manpage" \
	"$overrides"; do
	[[ -e "$path" ]] || { echo "Required package file is missing: ${path#"$root"/}" >&2; exit 1; }
done
[[ -x "$binary" ]] || { echo "Main binary is not executable." >&2; exit 1; }
[[ -L "$link" ]] || { echo "PATH command is not a symlink." >&2; exit 1; }

link_target=$(readlink "$link")
if [[ "$link_target" == /* ]]; then
	resolved=$(realpath -m "$root$link_target")
else
	resolved=$(realpath -m "$(dirname "$link")/$link_target")
fi
case "$resolved" in
	"$root/"*) ;;
	*) echo "PATH symlink escapes the package: $(readlink "$link")" >&2; exit 1 ;;
esac
[[ "$resolved" == "$binary" ]] || { echo "PATH symlink does not target the main binary." >&2; exit 1; }

grep -qx 'Exec=portfolio-jockey' "$desktop" || { echo "Desktop Exec does not match the PATH command." >&2; exit 1; }
grep -qx 'TryExec=portfolio-jockey' "$desktop" || { echo "Desktop TryExec does not match the PATH command." >&2; exit 1; }
grep -qx "Icon=$app_id" "$desktop" || { echo "Desktop icon name is incorrect." >&2; exit 1; }
desktop-file-validate "$desktop"
gzip -t "$changelog" "$manpage"
grep -Fqx 'embedded-library freetype [usr/lib/portfolio-jockey/lib/libflutter_linux_gtk.so]' "$overrides" || {
	echo "Missing documented Lintian override for Flutter's embedded Freetype." >&2
	exit 1
}
grep -Fqx 'embedded-library libjpeg [usr/lib/portfolio-jockey/lib/libflutter_linux_gtk.so]' "$overrides" || {
	echo "Missing documented Lintian override for Flutter's embedded JPEG library." >&2
	exit 1
}

check_dependencies() {
	local object=$1
	local missing
	missing=$(ldd "$object" | grep 'not found' || true)
	if [[ -n "$missing" ]]; then
		echo "Unresolved shared libraries in ${object#"$root"/}:" >&2
		printf '%s\n' "$missing" >&2
		exit 1
	fi
}

check_dependencies "$binary"
while IFS= read -r -d '' object; do
	check_dependencies "$object"
done < <(find "$root/usr/lib/portfolio-jockey/lib" -type f -name '*.so*' -print0)

control_dir="$root/DEBIAN"
if [[ "$mode" == --package ]]; then
	control_dir="$work/control"
	dpkg-deb -e "$target" "$control_dir"
fi
[[ -s "$control_dir/md5sums" ]] || { echo "DEBIAN/md5sums is missing." >&2; exit 1; }
(cd "$root" && md5sum --quiet -c "$control_dir/md5sums") || {
	echo "DEBIAN/md5sums does not match the package files." >&2
	exit 1
}
grep -Eq '^Installed-Size: [0-9]+$' "$control_dir/control" || {
	echo "DEBIAN/control has no Installed-Size." >&2
	exit 1
}

# Each pair must be one "first | second" alternative: the t64 names are what
# Debian 13 and Ubuntu 24.04 ship, the old names what Debian 12 and Ubuntu
# 22.04 ship. libsodium and Poppler are loaded through dart:ffi.
depends=$(sed -n 's/^Depends: //p' "$control_dir/control")
version='( \([^)]*\))?'
for pair in \
	'libatk1.0-0t64 libatk1.0-0' \
	'libglib2.0-0t64 libglib2.0-0' \
	'libgtk-3-0t64 libgtk-3-0' \
	'libpoppler-glib8t64 libpoppler-glib8' \
	'libsodium23 libsodium26'; do
	first=${pair% *}
	second=${pair#* }
	pattern=", ${first//./\\.}${version} \\| ${second//./\\.}${version},"
	[[ ", $depends," =~ $pattern ]] || {
		echo "Depends must offer '$first | $second'." >&2
		exit 1
	}
done
for old in libatk1.0-0 libglib2.0-0 libgtk-3-0 libpoppler-glib8; do
	pattern=", ${old//./\\.}${version},"
	[[ ! ", $depends," =~ $pattern ]] || {
		echo "Depends lists $old without its t64 alternative." >&2
		exit 1
	}
done

if [[ "$mode" == --package ]]; then
	owner_entries=$(dpkg-deb -c "$target" | grep -v ' root/root ' || true)
	if [[ -n "$owner_entries" ]]; then
		echo "Package entries are not root-owned." >&2
		exit 1
	fi
fi

printf 'Package layout checks passed (%s).\n' "$mode"
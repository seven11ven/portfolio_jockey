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

if [[ "$mode" == --package ]]; then
	depends=$(dpkg-deb -f "$target" Depends)
	for dependency in libpoppler-glib8 libsodium23; do
		[[ ",$depends," == *", $dependency,"* || ",$depends," == *",$dependency,"* ]] || {
			echo "Missing FFI runtime dependency: $dependency" >&2
			exit 1
		}
	done
	owner_entries=$(dpkg-deb -c "$target" | grep -v ' root/root ' || true)
	if [[ -n "$owner_entries" ]]; then
		echo "Package entries are not root-owned." >&2
		exit 1
	fi
fi

printf 'Package layout checks passed (%s).\n' "$mode"
# Before Debian packaging repair

This backup preserves the Debian packaging scripts and man page before the 2026-11-04 repair (t64 dependency alternatives, changelog-driven version and maintainer, clean release rebuild, relative command link, md5sums).

To restore, copy the files in `packaging/debian/` from this folder to `packaging/debian/` in the repository, and delete `packaging/debian/changelog`. No build artifacts or secrets are included.

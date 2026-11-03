# Before Debian shared-dependency checks

This backup preserves the live Debian release builder and package checker before adding dependency discovery and unresolved-library checks for every bundled shared object.

To restore, copy `packaging/debian/build.sh` and `packaging/debian/check.sh` from this folder back to `packaging/debian/` in the repository. No build artifacts or secrets are included.

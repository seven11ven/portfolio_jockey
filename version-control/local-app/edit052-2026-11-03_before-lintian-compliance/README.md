# Before Lintian compliance changes

This backup preserves the Debian release builder, package checker, and desktop entry before moving the private Flutter bundle under `/usr/lib`, adding Debian documentation files, and stripping packaged ELF objects.

To restore, copy the files from `packaging/debian/` in this backup to the repository's `packaging/debian/` directory. No generated packages or secrets are included.

# Before build cache fix

This backup preserves the Debian release builder before it also clears the Flutter build cache (`app/.dart_tool/flutter_build`).

To restore, copy `build.sh` from this folder to `packaging/debian/build.sh`. No build artifacts or secrets are included.

# Publishing a Linux Release

Portfolio Jockey's first release is an x86-64 Flatpak published as a GitHub Release. Flathub is a possible future distribution channel, but it is not part of this release process.

## Prepare the source

Before a release, review the complete commit range that will become public. Check that the source, documentation, tests, and release notes contain no secrets or private information. Run the required checks:

```sh
bash .devcontainer/check-lockdown.sh
cd app
bash tool/check-privacy.sh
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Commit the approved source changes. The packaging script requires a clean working tree and records the exact source commit in the build kit.

## Generate the build kit

From the repository root, run:

```sh
bash app/tool/package-bundle.sh
```

This repeats the checks, builds the Linux release bundle, and creates files under `packaging/flatpak/dist/`. The `portfolio-jockey-build-kit-<version>.tar.gz` archive is for the desktop packager; it is not a release asset. Verify its transfer checksum with `sha256sum`.

## Build and test on Linux

Transfer and extract the build kit on an x86-64 Linux desktop with Flatpak and `flatpak-builder` installed, then run:

```sh
bash build.sh
```

The script verifies the kit, builds and installs the Flatpak, and prints SHA-256 checksums for the app and bundled-library source packages. It downloads the pinned runtime and build dependencies from Flathub; the installed app itself has no network permission.

Complete the kit's `TESTING.md` checklist using disposable files. In particular, verify that **Show original in file manager** reveals the original, that moving it to Trash and restoring it works, and that the encrypted project copy remains. Also verify the original-missing state and that notification messages dismiss when clicked or tapped. Direct Trash and **Trash original, delete copy** are not available inside the Flatpak.

## Prepare the GitHub Release

Publish exactly these three files:

- `portfolio-jockey-<version>-x86_64.flatpak`
- `portfolio-jockey-<version>-sources.flatpak`
- `portfolio-jockey-source-<version>.tar.gz`

Do not upload the build kit or the intermediate `portfolio-jockey-bundle-<version>-x86_64.tar.gz`.

The desktop build prints checksums for the two `.flatpak` files. Calculate them again from the files with:

```sh
sha256sum portfolio-jockey-<version>-x86_64.flatpak portfolio-jockey-<version>-sources.flatpak
```

The repository-side `package-bundle.sh` prints the app-source archive checksum. It can also be recalculated from the repository root:

```sh
sha256sum packaging/flatpak/dist/portfolio-jockey-source-<version>.tar.gz
```

Include every SHA-256 in the release notes beside its filename. Link to the installation guide at `docs/install.md` in the tagged source tree.

Use the tag `v<version>` and make it point to the exact commit recorded in the build kit's `SOURCE_COMMIT`. For example, version `0.1.0` uses the tag `v0.1.0`. Review the tag target, asset names, checksums, release notes, and public commit history before publishing.

After publishing, verify that all three assets are downloadable and that the installation-guide link resolves at the release tag.
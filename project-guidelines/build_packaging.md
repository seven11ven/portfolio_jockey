# This is a guideline regarding Builds and their Packaging


## Expectations
* APKs, .debs, or any form of executable or build should go under "/project-builds"
	- If "/project-builds" doesn't exist, create it. This is a strict folder structure you MUST follow.
		- If the build is a test/dev build: "/project-builds/dev-builds/(build-name)"
		- If the build is a release build: "/project-builds/release-builds/(build-name)""
	- A "build summary" should be logged in "/project-builds/logs"
* Builds MUST have properly bundled all proper dependencies/components required for it to run. Always check the valadity of said build(s) for any missing components, scripts, packages, or dependencies that otherwise prevent it from running on a machine.
* Always ask the user which type the build is(release, or dev), then send the build to it's respective folder
* Builds MUST be checked against all known issues / issues listed(see section: "Known Errors for Builds")
* Check the naming convention of the build type. If it defers from what it's packaging expects, it WILL NOT WORK.
* You are to NEVER clean old builds unless the user expresses EXPLICIT PERMISSION TO DO SO.
* Every path listed in a ".desktop" file MUST be correct and match the EXACT PATH of the application
* The naming convention for the Build(s) folder(s) is as follows:
    - "(Release Name Here)-(Platform Type)-(Version)"


## Rules
### Linux packaging (.deb)

#### Project values (fill in per project)
- Package name: `<pkg-name>`  (lowercase; letters, digits, `+ - .`)
- Install dir: `/opt/<app_dir>/`
- Main binary: `/opt/<app_dir>/<binary>`
- Command on PATH: `/usr/bin/<command>` → symlink to the main binary
- Desktop file: `/usr/share/applications/<app-id>.desktop`
- Icon name: `<icon-name>`

#### Naming and versioning
- The version goes only in `Version:`, never in `Package:` or in paths.
  Otherwise each release installs as a separate package and never upgrades.
- Output filename follows `<pkg-name>_<version>_<arch>.deb`.
- Don't put `linux` or the architecture in the package name.
- Treat every name above as exact. Dashes and underscores are not
  interchangeable; check each reference character by character.

#### Build
- Package release builds only, never debug builds. Know what your
  toolchain's release output looks like and confirm it before packaging.
- Ship the whole runtime bundle (libraries, data, assets) the binary
  expects relative to itself.

#### Installed layout
- If the app lives outside PATH (e.g. `/opt`), ship a symlink in `/usr/bin`.
  Users must be able to start the app by typing a command.
- Scripts need LF line endings and a shebang pointing to an interpreter
  that is either always present or listed in `Depends:`.

#### Desktop entry
- `Exec=` must resolve after install: either an absolute path to a file the
  package ships, or a command name the package puts on PATH. Menus silently
  hide entries whose command can't be found.
- `TryExec=`, if used, follows the same rule.
- Every `Icon=` name must match an icon file the package ships, under
  `/usr/share/icons/hicolor/<size>/apps/` (PNG) or `.../scalable/apps/` (SVG).
- `Categories=` contains exactly one main category plus optional extras.
- `StartupWMClass=` matches the window class the app actually sets.
- The file must pass `desktop-file-validate` with no errors.

#### Dependencies
- Every shared library or runtime the app loads at run time and that isn't
  in the bundle goes in `Depends:`. Check with `ldd` on the binary and
  bundled libraries, and account for libraries loaded dynamically by plugins.

#### Renames and moves
- When a binary, directory, desktop file or icon is renamed or moved, update
  every reference in the same change: the symlink, `Exec=`, `TryExec=`,
  `Icon=`, `StartupWMClass=`, maintainer scripts and build scripts.
  Search the repo for the old name before finishing.

#### Verification (required before reporting done)
1. Build the .deb and extract it: `dpkg-deb -x <file>.deb /tmp/pkgcheck`.
2. Confirm the main binary exists and is executable, the PATH symlink
   resolves inside the extracted tree, and `Exec=` and `Icon=` point to
   shipped files.
3. Run `desktop-file-validate` on the extracted desktop file.
4. Check `dpkg-deb -f <file>.deb Package Version Depends` for the rules above.
5. If a test machine or container is available, install the package and
   confirm both the terminal command and the menu entry launch the app.
- If the project has a check script (e.g. `scripts/check-deb.sh`), run it
  and do not report the task done until it passes.
- Report any check you could not run instead of assuming it passed.

## Known Errors for Builds
### .debian packages
#### Kotlin standard library Error
```
Exception in thread "main" java.lang.NoClassDefFoundError: kotlin/coroutines/CoroutineContext$Element
	at java.base/java.lang.ClassLoader.defineClass1(Native Method)
	at java.base/java.lang.ClassLoader.defineClass(Unknown Source)
	at java.base/java.security.SecureClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.findClassOnClassPathOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClassOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.defineClass1(Native Method)
	at java.base/java.lang.ClassLoader.defineClass(Unknown Source)
	at java.base/java.security.SecureClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.findClassOnClassPathOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClassOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.defineClass1(Native Method)
	at java.base/java.lang.ClassLoader.defineClass(Unknown Source)
	at java.base/java.security.SecureClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.findClassOnClassPathOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClassOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.defineClass1(Native Method)
	at java.base/java.lang.ClassLoader.defineClass(Unknown Source)
	at java.base/java.security.SecureClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.defineClass(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.findClassOnClassPathOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClassOrNull(Unknown Source)
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.loadClass(Unknown Source)
	at kotlinx.coroutines.SupervisorKt.SupervisorJob(Supervisor.kt:27)
	at kotlinx.coroutines.SupervisorKt.SupervisorJob$default(Supervisor.kt:27)
	at dev.recorddisc.player.MainKt.main(main.kt:36)
	at dev.recorddisc.player.MainKt.main(main.kt)
Caused by: java.lang.ClassNotFoundException: kotlin.coroutines.CoroutineContext$Element
	at java.base/jdk.internal.loader.BuiltinClassLoader.loadClass(Unknown Source)
	at java.base/java.lang.ClassLoader.loadClass(Unknown Source)
	... 36 more

```
* The error means the Kotlin standard library (kotlin-stdlib) isn’t on the classpath when the packaged app runs. kotlinx.coroutines was found, since SupervisorJob started loading, but kotlin.coroutines.CoroutineContext lives in kotlin-stdlib, and that jar is missing. Your code and dependencies compiled fine. The packaging step just didn’t ship the stdlib.
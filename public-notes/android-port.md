# Android port: on hold

**Decided:** 2026-10-22, by the project manager
**Status:** Portfolio Jockey is built for **Linux only** for now. The Android port will be revisited later.

## Why
Building Android apps requires accepting Google's **Android Software Development Kit License Agreement** (dated April 28, 2026, at https://developer.android.com/studio). The project manager declined it for now because of the legal room it gives Google. The terms of concern:

- **Indemnity (section 12):** you agree to cover Google's costs if someone sues Google over your use of the SDK or your apps.
- **One-sided control (sections 3.6, 9, 10, 11):** Google can change or stop providing the SDK at any time and end the agreement in some cases. The SDK comes "as is", with no warranty, and Google's liability is limited.
- **Usage statistics (section 6):** Google may collect a unique ID, IP address, versions and tool usage. This is only with consent, but anonymized, aggregated data may be shared with Google's partners.
- **Restrictions (section 3):** the SDK may only be used to build apps for "compatible" Android devices, and may not be modified, redistributed or reverse engineered.
- **Jurisdiction (section 14):** California law, with disputes in Santa Clara County courts.

The individual SDK packages (`sdkmanager --licenses`) carry extra license texts that would also need review.

## What this changes in the plan
- Phase 2: no Android SDK and no JDK. Flutter is set up for Linux desktop only.
- Phase 3: `flutter create` with the Linux platform only.
- Phases 5–6: the Kotlin bridge (deleting originals through Android's file permissions, the folder picker, "Edit in another app" through `FileProvider`) is postponed.
- Phase 8: Linux packaging only (Flatpak with no network). No APK.
- The approved mockups keep their phone layouts as the design reference for the future port.
- Keep the app's core (the vault, encryption, index, and the UI in Dart) free of Linux-only assumptions where that costs little, so the port stays possible.

## When we come back to it
Options to research then, each checked against the guidelines (Budgeting, Open Source and Privacy, Security):
1. Accept Google's SDK license after a fresh read, since its terms may have changed.
2. Look for SDK builds made from the open-source Android project (AOSP, Apache 2.0) instead of Google's distribution, for example community or distro packages. Check whether they're current enough for Flutter, and whether Flutter's Android build still pulls in Google-licensed parts (Gradle plugin, Maven artifacts).
3. Check how F-Droid builds apps, since it focuses on free software.
None of these have been verified yet.

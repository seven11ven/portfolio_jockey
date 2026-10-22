import 'dart:io';

/// Whether the app runs inside a Flatpak sandbox (Flatpak puts this file at
/// the sandbox's root). Inside one, files outside the app's own folders are
/// reached through the desktop's portals, so the app suggests no
/// `~/Documents` paths and lets the desktop's dialogs choose.
bool runningInFlatpak() => File('/.flatpak-info').existsSync();

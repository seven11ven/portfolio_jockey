# Which Linux systems Portfolio Jockey will run on

Portfolio Jockey will be released as a **Flatpak**. A Flatpak brings its own libraries with it, so the app doesn't depend on your distribution's library versions. Any 64-bit Linux desktop that can run Flatpak should be able to install it.

This describes the **planned** support. The app isn't released yet. Each distribution below gets tested when the Flatpak is built (plan phase 8).

Last checked: 2026-10-22, against Flutter's [supported platforms](https://docs.flutter.dev/reference/supported-platforms) and Flathub's [setup pages](https://flathub.org/setup/).

## Major distributions

| Distribution | Flatpak | To get it |
|---|---|---|
| **Fedora** Workstation, Silverblue, Kinoite | Built in | Nothing to do |
| **Linux Mint** 18.3 and newer | Built in | Nothing to do |
| **Pop!_OS** 20.04 and newer | Built in | Nothing to do |
| **Ubuntu** 18.10 and newer (Flutter supports 20.04 LTS to 24.04 LTS) | Install it once | `sudo apt install flatpak` |
| **Debian** 10 and newer (Flutter supports 10 to 13) | Install it once | `sudo apt install flatpak` |
| **Arch Linux** | Install it once | `sudo pacman -S flatpak` |

Flutter, the framework the app is built with, officially supports and tests **Debian** and **Ubuntu**. On every other distribution, the app runs on the Flatpak's own runtime, not the system's libraries.

**Other distributions** with official Flatpak setup instructions on [flathub.org/setup](https://flathub.org/setup/) should also work. They include openSUSE, Manjaro, elementary OS, Zorin OS, Kubuntu, KDE neon, EndeavourOS, MX Linux, Rocky Linux, AlmaLinux, Red Hat Enterprise Linux, CentOS Stream, Solus, Void Linux, NixOS, Gentoo, Vanilla OS and Endless OS.

## Requirements
- **A 64-bit processor.** **x64** (Intel/AMD) will be supported. **arm64** (e.g. ARM laptops, Raspberry Pi 4/5 with a 64-bit OS) is supported by Flutter. It needs its own build, decided in phase 8.
- **A graphical desktop** (Wayland or X11) with OpenGL. Software rendering works on machines without a graphics card.
- **Flatpak** installed (see the table).
- **No internet connection is needed** to use the app. It never connects to the network.

## Not supported
- 32-bit processors, RISC-V and other processor types (Flutter doesn't support them).
- Servers or systems with no graphical desktop.
- Distributions that can't run Flatpak.
- Android: the port is on hold (see `android-port.md`).

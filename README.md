# Sevenfold

**Automatic app signing.**

Sevenfold keeps your sideloaded apps signed using your own Apple ID. It automatically renews signatures before they expire, following the schedule you configure — even while your device is locked. No computer or paid Apple Developer account required.

Available on [Havoc](https://havoc.app).

## Features

**Signing**
- Scheduled automatic signing with customizable days and times
- Optional conditions: Wi-Fi only, charging only, and Low Power Mode support
- Automatic retries every 30 minutes, up to three attempts
- Parallel signing for up to three apps, with automatic fallback to sequential signing when Apple limits requests
- Direct `.ipa` installation from the Files app or a URL

**Account & Certificates**
- App ID usage tracker for free Apple accounts (10 per week)
- Certificate management: both certificate slots, registered devices, expiration dates and serial numbers
- Certificate sharing between devices
- Two-factor authentication, with credentials stored in the device keychain

**Reliability & Diagnostics**
- Automatic fallback between anisette servers, with support for custom servers
- Lock-screen notifications for successful runs, failures and apps approaching expiration
- Signing history with detailed error information
- Diagnostics, including a background signing test

**Interface**
- Nine languages: English, 简体中文, Español, Português, Русский, Bahasa Indonesia, 日本語, हिन्दी, العربية (full right-to-left support)
- Native iPad layout with sidebar navigation
- Guided first-launch setup

## Requirements

- iOS 15 or later
- Rootless or RootHide jailbreak

Packages: `com.t4mag0.sevenfold_<version>_iphoneos-arm64.deb` (rootless) and `com.t4mag0.sevenfold_<version>_iphoneos-arm64e.deb` (RootHide).

## Build on Windows

Uses WSL (Ubuntu running inside Windows). One-time setup:

1. Open PowerShell as administrator and run `wsl --install -d Ubuntu-24.04`,
   then restart and create your Ubuntu user when asked.
2. Double-click `build-on-windows.cmd` in this folder. The first run installs
   the build tools (about 10 minutes); later runs take about a minute.
3. The two `.deb` files appear in the `packages` folder next to it.

## Build on Linux / inside WSL by hand

```sh
./tools/setup-wsl.sh                 # once
export THEOS=~/sevenfold-tools/theos
./packaging/build-packages.sh        # -> packages/*.deb
```

## Layout

| Folder | What's in it |
| --- | --- |
| `app/` | Theos project for the app (Info.plist, icons) |
| `daemon/` | Theos project for the background service `sevenfoldd` |
| `iOS/Sevenfold/` | Interface and app features |
| `Shared/Engine/` | Apple sign-in, provisioning and signing engine |
| `Shared/Engine/Sevenfold/` | Server list and fallback, event log, device models |
| `Shared/Apps/` | Finding installed apps and the signing pipeline |
| `Shared/Daemon/` | Background service: schedule, wake-ups, launching the app |
| `packaging/` | Package scripts and launch daemon plist |
| `tools/` | Build-tool setup for WSL/Linux |
| `vendor/openssl/` | Prebuilt OpenSSL 1.0.2 (arm64) |
| `art/` | App icon source |

Identifiers: app `com.t4mag0.sevenfold`, background service `com.t4mag0.sevenfoldd`, keychain service `com.t4mag0.sevenfold`.

## Credits

**Inspiration**
- Matchstic (Matt Clarke) — ReProvision, the original on-device signing app that inspired Sevenfold

**Anisette servers**
- Dadoum — anisette-v3-server and the Provision project
- SideStore Team — public anisette server
- nab138 — iloader and its public anisette server
- Jackson Coxson (jkcoxson) — public anisette server
- StikStore — public anisette server

**Apple sign-in research**
- Riley Testut — AltStore and AltSign
- libimobiledevice project

**Open-source components** (details and licenses in [NOTICE](NOTICE))
- ldid — Jay Freeman (saurik), maintained by the Procursus Team (AGPL-3.0)
- libplist — libimobiledevice project (LGPL-2.1)
- SSZipArchive and minizip — ZipArchive contributors, Gilles Vollant and Nathan Moinvaziri (MIT / zlib)
- SAMKeychain — Sam Soffes (MIT)
- NSData+GZIP — Nick Lockwood (zlib)
- OpenSSL — The OpenSSL Project

## License

By T4MAG0. Sevenfold is licensed under the GNU Affero General Public License v3.0 — see [LICENSE](LICENSE).

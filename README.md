<p align="center">
  <img src="assets/icon_monet.png" width="120" height="120" alt="MangaLoader Icon" />
</p>

<h1 align="center">MangaLoader</h1>

<p align="center">
  A fast, lightweight, and offline-capable manga and comic reader built with Flutter and a native Rust core engine.
</p>

<p align="center">
  <a href="https://github.com/imsudoer/mangaloader/releases/latest"><img src="https://img.shields.io/github/v/release/imsudoer/mangaloader?style=flat-square&color=8A897C&label=Release" alt="Latest Release" /></a>
  <a href="https://github.com/imsudoer/mangaloader/releases/latest"><img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-37474F?style=flat-square" alt="Supported Platforms" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.29-02569B?style=flat-square" alt="Flutter" /></a>
  <a href="https://rustup.rs"><img src="https://img.shields.io/badge/Rust-1.80+-DEA584?style=flat-square" alt="Rust" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL%203.0-455A64?style=flat-square" alt="License" /></a>
</p>

<p align="center">
  <a href="#screenshots">Screenshots</a> •
  <a href="#downloads">Downloads</a> •
  <a href="#key-features">Key Features</a> •
  <a href="#keyboard-shortcuts-pc">Keyboard Shortcuts</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#building-from-source">Building from Source</a>
</p>

---

## Screenshots

<p align="center">
  <img src="promo_screens/2_home_screen.jpg" width="31%" alt="Home Screen" />
  <img src="promo_screens/3_catalog_search.jpg" width="31%" alt="Catalog & Search" />
  <img src="promo_screens/4_offline_download.jpg" width="31%" alt="Manga Details & Downloads" />
</p>

---

## Downloads

Compiled binaries for all supported platforms are available on the [Releases](https://github.com/imsudoer/mangaloader/releases/latest) page:

| Platform | Package | Description |
| :--- | :--- | :--- |
| **Android (Universal)** | [`mangaloader-android-universal.apk`](https://github.com/imsudoer/mangaloader/releases/latest) | Single package for all architectures (ARM64, ARMv7, x86) |
| **Android (ARM64)** | [`mangaloader-android-arm64-v8a.apk`](https://github.com/imsudoer/mangaloader/releases/latest) | Smaller APK for modern 64-bit devices |
| **Android (ARMv7)** | [`mangaloader-android-armeabi-v7a.apk`](https://github.com/imsudoer/mangaloader/releases/latest) | Legacy 32-bit Android phones and tablets |
| **Windows** | [`mangaloader-windows-x64.zip`](https://github.com/imsudoer/mangaloader/releases/latest) | Portable archive (extract and run `mangaloader.exe`) |
| **Linux** | [`mangaloader-linux-x64.tar.gz`](https://github.com/imsudoer/mangaloader/releases/latest) | Standalone release bundle for Linux x64 |

In the application settings (*Settings -> Updates*), you can choose between the **Stable** channel (regular verified releases) and the **Beta/Dev** channel (rolling nightly builds).

---

## Key Features

### Reader Engine
- **Multiple Reading Modes**:
  - Vertical continuous Webtoon strip layout optimized for manhwa with seamless image concatenation.
  - Standard paged modes (Right-to-Left for Japanese manga, Left-to-Right for western comics).
- **Hands-Free Auto-Scroll**: Smooth automated viewport scrolling with on-the-fly speed controls.
- **Image Post-Processing**:
  - Edge sharpening filters (Subtle and High) to improve scan text definition.
  - Dynamic white-border cropping with adjustable zoom margin.
  - Color themes: Light, Dark, and deep AMOLED Black for OLED battery saving.
- **Quick Navigation**: Floating chapter picker and seamless transition to the next chapter.

### Background Downloader & Offline Storage
- **Native Multi-Threaded Engine**: Asynchronous chapter fetching via Rust (`tokio` and `reqwest`) with automated CDN failover upon connection drops.
- **Standard CBZ Format**: Downloaded chapters are packaged into standard `.cbz` archives, fully readable offline and compatible with external comic applications.
- **Storage Management**: Optional automated deletion of read chapters and one-click image cache cleanup.

### MangaLib Account Integration
- **Secure Web Authentication**: In-app login with automatic session cookie detection.
- **Bookmark Synchronization**: Synchronizes user reading lists (*Reading*, *Plan to Read*, *Completed*, *Favorites*, *Dropped*).
- **Scale Optimized**: Virtualized list views and limited image cache sizes ensure fluid UI performance even on large libraries with 1,000+ titles.

### Manga Recap & Statistics
- Personal reading analytics: track chapters read, pages turned, total reading time, and top genres.
- Exportable summary card for sharing reading achievements.

### Background Notifications
- Periodic background check for newly released chapters with native local push notifications.

---

## Keyboard Shortcuts (PC)

| Key / Shortcut | Action |
| :--- | :--- |
| `Space` / `Down Arrow` / `J` | Scroll down / Next page |
| `Up Arrow` / `K` | Scroll up / Previous page |
| `Left Arrow` | Previous page (in RTL mode) |
| `Right Arrow` | Next page (in RTL mode) |
| `F` / `F11` | Toggle Fullscreen |
| `Escape` | Exit reader / Navigate back |
| `Double Click` | Toggle 2x Zoom |

---

## Architecture

```
+-------------------------------------------------------------+
|                      Flutter Frontend                       |
|        (UI, Riverpod State, GoRouter, Theme, Pages)         |
+------------------------------+------------------------------+
                               |  flutter_rust_bridge v2
+------------------------------v------------------------------+
|                      Rust Core Engine                       |
|  +--------------------+  +-------------------------------+  |
|  |  mangalib_client   |  |        download_engine        |  |
|  |  (Async HTTP, API) |  |   (Tokio Chunks, Concurrency) |  |
|  +--------------------+  +-------------------------------+  |
|  +--------------------+  +-------------------------------+  |
|  |     cbz_export     |  |            storage            |  |
|  |  (Zip, CBZ Reader) |  |    (SQLite Rusqlite, DB)      |  |
|  +--------------------+  +-------------------------------+  |
+-------------------------------------------------------------+
```

---

## Building from Source

### Prerequisites
- [Flutter SDK](https://flutter.dev) (3.29+)
- [Rust Toolchain](https://rustup.rs) (stable)
- Code generator: `cargo install flutter_rust_bridge_codegen --version 2.12.0`
- For Android builds: Android SDK, NDK (r26b+), and `cargo install cargo-ndk`
- For Linux builds: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`

### 1. Clone the repository
```bash
git clone https://github.com/imsudoer/mangaloader.git
cd mangaloader
```

### 2. Generate bridge bindings & fetch dependencies
```bash
flutter_rust_bridge_codegen generate
flutter pub get
```

### 3. Build for Windows (x64)
```bash
flutter build windows --release
```
The output binary will be located in `build/windows/x64/runner/Release/`.

### 4. Build for Linux (x64)
```bash
flutter build linux --release
```
The application bundle will be created in `build/linux/x64/release/bundle/`.

### 5. Build for Android
```bash
# Universal APK (all architectures)
flutter build apk --release

# Split APKs (per-architecture)
flutter build apk --release --split-per-abi
```
Generated APK files will be located in `build/app/outputs/flutter-apk/`.

---

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

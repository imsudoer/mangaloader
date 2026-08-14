# MangaLoader

A high-performance, cross-platform manga, manhwa, and manhua reader and downloader built with Flutter and a native Rust core engine.

[![Latest Release](https://img.shields.io/github/v/release/imsudoer/mangaloader?style=flat-square&color=607D8B&label=Release)](https://github.com/imsudoer/mangaloader/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-37474F?style=flat-square)](https://github.com/imsudoer/mangaloader/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.29-02569B?style=flat-square)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-1.80+-DEA584?style=flat-square)](https://rustup.rs)

[Downloads](https://github.com/imsudoer/mangaloader/releases/latest) • [Features](#features) • [Keyboard Shortcuts](#keyboard-shortcuts-pc) • [Architecture](#architecture) • [Building from Source](#building-from-source)

---

## Overview

MangaLoader combines a reactive, minimalistic Flutter user interface with a multi-threaded Rust core engine connected via `flutter_rust_bridge`. It is designed for fast browsing, high-throughput batch downloads, and comfortable reading across desktop (Windows) and mobile (Android) devices.

---

## Features

### Reader Engine
- **Continuous Webtoon Scrolling**: Optimized for long-strip manhwa formats with seamless vertical rendering, preventing layout jumps and image cutoff.
- **Standard Paged Modes**: Right-to-Left (Manga) and Left-to-Right reading modes.
- **Image Post-Processing Filters**:
  - Sharpening filters (Subtle / High) to enhance text line definition.
  - Color filters: Sepia, Dark Inversion, and standard rendering.
  - Dynamic white border cropper with adjustable zoom percentage.
- **Smart HUD**: Minimalistic overlay displaying current time, battery percentage, and progress counter without obstructing content.
- **Hands-Free Auto-Scroll**: Configurable scroll velocity with smooth viewport animation.
- **True Fullscreen Mode**: Immersive reading without window frames or system bars on desktop and mobile.

### Rust Download Engine & Offline CBZ Storage
- **High-Throughput Concurrency**: Multi-threaded parallel chapter and page fetching utilizing `tokio` and `reqwest`.
- **CBZ Archive Packaging**: Automatically compiles downloaded chapters into standard `.cbz` archives.
- **ComicInfo.xml Metadata**: Automatically generates and injects metadata (title, chapter, volume, author, genres, description) compatible with external comic servers and viewers (Kavita, Komga, Tachiyomi, CDisplayEx).
- **Built-in Offline Reader**: Direct playback and navigation for locally saved CBZ files.

### Library & Progress Tracking
- **Mutually Exclusive Shelves**: Organize titles into distinct categories: Reading, Plan to Read, Completed, Favorites, On Hold, and Dropped.
- **Automatic Library Enrollment**: Titles are automatically added to the Reading shelf as soon as a chapter is opened.
- **Visual Progress Indicator**: Dedicated progress bar on library cards showing exact reading completion and last read chapter.
- **Backup & Migration**: One-click JSON export and import for user library, bookmarks, and reading history.

### Catalog Integration
- Advanced search with multi-tag filtering, genres, content types, and sorting.
- Related series and similar title carousels on the manga details page.
- Threaded MangaLib comments system supporting avatars, replies, and vote scores.

### In-App Updates & Localization
- **GitHub Release Checker**: In-app updater that checks `imsudoer/mangaloader` releases, displays changelogs, and provides direct downloads for APK and Windows binaries.
- **Localization**: Full Russian and English language support with automatic system locale detection and manual switching in settings.

---

## Keyboard Shortcuts (PC)

| Key / Shortcut | Action |
| :--- | :--- |
| `Space` / `Down Arrow` / `J` | Scroll down / Next page |
| `Up Arrow` / `K` | Scroll up / Previous page |
| `Left Arrow` | Previous page (RTL mode) |
| `Right Arrow` | Next page (RTL mode) |
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
|  |  (Zip, ComicInfo)  |  |    (SQLite Rusqlite, DB)      |  |
|  +--------------------+  +-------------------------------+  |
+-------------------------------------------------------------+
```

---

## Building from Source

### Prerequisites
- [Flutter SDK](https://flutter.dev) (3.29+)
- [Rust Toolchain](https://rustup.rs) (stable)
- `cargo install flutter_rust_bridge_codegen --version 2.12.0`
- For Android builds: Android SDK, NDK (r26b+), and `cargo install cargo-ndk`

### 1. Clone the repository
```bash
git clone https://github.com/imsudoer/mangaloader.git
cd mangaloader
```

### 2. Generate bridge bindings and install dependencies
```bash
flutter_rust_bridge_codegen generate
flutter pub get
```

### 3. Build for Windows (x64)
```bash
flutter build windows --release
```
Binaries will be placed in `build/windows/x64/runner/Release/`.

### 4. Build for Android (Split ABI APKs)
```bash
# Add Rust targets for Android architectures
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Compile release APKs
flutter build apk --release --split-per-abi
```
Generated APK files will be located in `build/app/outputs/flutter-apk/`.

---

## License

MangaLoader is distributed for personal, non-commercial use. All rights to manga materials belong to their respective authors and publishers.

<p align="center">
  <img src="assets/icon_monet.png" width="120" height="120" alt="MangaLoader Icon" />
</p>

<h1 align="center">MangaLoader</h1>

<p align="center">
  Кроссплатформенный клиент для комфортного онлайн-чтения и фонового скачивания манги с каталога MangaLib.
  <br>
  Fast, lightweight, and offline-capable manga reader built with Flutter and a native Rust backend.
</p>

<p align="center">
  <a href="https://github.com/imsudoer/mangaloader/releases/latest"><img src="https://img.shields.io/github/v/release/imsudoer/mangaloader?style=flat-square&color=8A897C&label=Release" alt="Latest Release" /></a>
  <a href="https://github.com/imsudoer/mangaloader/releases/latest"><img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-37474F?style=flat-square" alt="Supported Platforms" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.29-02569B?style=flat-square" alt="Flutter" /></a>
  <a href="https://rustup.rs"><img src="https://img.shields.io/badge/Rust-1.80+-DEA584?style=flat-square" alt="Rust" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL%203.0-455A64?style=flat-square" alt="License" /></a>
</p>

<p align="center">
  <a href="#скриншоты--screenshots">Скриншоты</a> •
  <a href="#скачать--downloads">Скачать</a> •
  <a href="#основные-возможности">Возможности</a> •
  <a href="#горячие-клавиши-пк">Горячие клавиши</a> •
  <a href="#архитектура">Архитектура</a> •
  <a href="#сборка-из-исходников--building-from-source">Сборка</a>
</p>

---

## Скриншоты / Screenshots

<p align="center">
  <img src="promo_screens/2_home_screen.jpg" width="31%" alt="Главный экран" />
  <img src="promo_screens/3_catalog_search.jpg" width="31%" alt="Каталог и поиск" />
  <img src="promo_screens/4_offline_download.jpg" width="31%" alt="Страница тайтла и загрузка" />
</p>

---

## Скачать / Downloads

Готовые сборки под все поддерживаемые платформы доступны на странице [Releases](https://github.com/imsudoer/mangaloader/releases/latest):

| Платформа | Файл пакета | Описание |
| :--- | :--- | :--- |
| **Android (Universal)** | [`mangaloader-android-universal.apk`](https://github.com/imsudoer/mangaloader/releases/latest) | Единый файл для всех устройств (ARM64, ARMv7, x86) |
| **Android (ARM64)** | [`mangaloader-android-arm64-v8a.apk`](https://github.com/imsudoer/mangaloader/releases/latest) | Облегченный APK для большинства современных смартфонов |
| **Android (ARMv7)** | [`mangaloader-android-armeabi-v7a.apk`](https://github.com/imsudoer/mangaloader/releases/latest) | APK для старых 32-битных смартфонов и планшетов |
| **Windows** | [`mangaloader-windows-x64.zip`](https://github.com/imsudoer/mangaloader/releases/latest) | Портативный архив (распаковать и запустить `mangaloader.exe`) |
| **Linux** | [`mangaloader-linux-x64.tar.gz`](https://github.com/imsudoer/mangaloader/releases/latest) | Тарбол со скомпилированным бандлом для Linux x64 |

В настройках приложения (*Настройки -> Обновления*) можно переключать канал обновлений между **Stable** (проверенные релизы) и **Beta/Dev** (свежие ночные сборки).

---

## Основные возможности

### Читалка
- **Режимы отображения**:
  - Вертикальная вебтун-лента с непрерывной подгрузкой для комфортного чтения манхвы и длинных полос.
  - Постраничный режим (справа налево для японской манги, слева направо для западных комиксов).
- **Автоматическая прокрутка (автоскролл)**: плавное движение страницы вниз с регулировкой скорости на лету.
- **Обработка сканов**:
  - Фильтры резкости (Subtle / High) для восстановления читаемости мелкого текста на сжатых сканах.
  - Обрезка пустых белых полей по краям с регулировкой масштаба.
  - Цветовые профили: темный, светлый и глубокий AMOLED-черный.
- **Быстрая навигация**: всплывающее меню выбора глав и переход к следующей/предыдущей главе без выхода в каталог.

### Фоновая загрузка и офлайн-режим
- **Нативное ядро загрузки**: многопоточное скачивание глав через Rust (`tokio` + `reqwest`) с автоматическим перебором рабочих CDN-зеркал при сетевых сбоях.
- **Стандартный формат CBZ**: скачанные главы упаковываются в архивы `.cbz`, которые можно читать прямо в приложении или открывать в сторонних читалках.
- **Очистка памяти**: настраиваемое автоудаление прочитанных глав и очистка дискового кэша изображений.

### Интеграция с MangaLib
- **Авторизация**: вход в аккаунт через защищенный браузер с сохранением сессии.
- **Синхронизация списков**: автоматический импорт и обновление закладок («Читаю», «В планах», «Прочитано», «Любимое», «Брошено»).
- **Оптимизация под большие коллекции**: виртуализированные списки и ограниченный размер кэша текстур гарантируют плавность интерфейса даже при библиотеках на 1000+ тайтлов.

### Статистика и итоги (Manga Recap)
- Подробный подсчет прочитанных глав, страниц, времени чтения и любимых жанров.
- Экспорт персональной графической карточки с итогами активности.

### Фоновые уведомления
- Периодическая фоновая проверка выхода новых глав для тайтлов из списков пользователя с push-уведомлениями.

---

## Горячие клавиши (ПК)

| Клавиша / Сочетание | Действие |
| :--- | :--- |
| `Пробел` / `Стрелка вниз` / `J` | Прокрутка вниз / Следующая страница |
| `Стрелка вверх` / `K` | Прокрутка вверх / Предыдущая страница |
| `Стрелка влево` | Предыдущая страница (в режиме RTL) |
| `Стрелка вправо` | Следующая страница (в режиме RTL) |
| `F` / `F11` | Полноэкранный режим |
| `Escape` | Выход из читалки / Назад |
| `Двойной клик` | Переключение масштаба 2x |

---

## Архитектура

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

## Сборка из исходников / Building from Source

### Требования
- [Flutter SDK](https://flutter.dev) (3.29+)
- [Rust Toolchain](https://rustup.rs) (stable)
- Кодогенератор моста: `cargo install flutter_rust_bridge_codegen --version 2.12.0`
- Для сборки Android: Android SDK, NDK (r26b+) и `cargo install cargo-ndk`
- Для сборки Linux: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`

### 1. Клонирование репозитория
```bash
git clone https://github.com/imsudoer/mangaloader.git
cd mangaloader
```

### 2. Генерация моста и установка зависимостей
```bash
flutter_rust_bridge_codegen generate
flutter pub get
```

### 3. Сборка под Windows (x64)
```bash
flutter build windows --release
```
Скомпилированное приложение будет находиться в папке `build/windows/x64/runner/Release/`.

### 4. Сборка под Linux (x64)
```bash
flutter build linux --release
```
Бинарный бандл будет собран в `build/linux/x64/release/bundle/`.

### 5. Сборка под Android
```bash
# Универсальный APK со всеми архитектурами
flutter build apk --release

# Либо раздельные сплит-APK
flutter build apk --release --split-per-abi
```
Собранные APK будут доступны в папке `build/app/outputs/flutter-apk/`.

---

## Лицензия / License

Проект распространяется под свободной лицензией GNU General Public License v3.0. Подробности в файле [LICENSE](LICENSE).

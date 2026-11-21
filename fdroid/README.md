# F-Droid

В репозитории подготовлены оба пути публикации: собственный репозиторий на
GitHub Pages и заявка в основной репозиторий F-Droid. Это разные каналы с разными
подписями, пользователь выбирает один.

| Файл | Назначение |
| :--- | :--- |
| `fastlane/metadata/android/{en-US,ru-RU}/` | Название, описания, changelog, иконка и скриншоты. F-Droid читает их из исходников. |
| `fdroid/bshv.mangaloader.app.yml` | Метаданные для основного репозитория fdroiddata. |
| `fdroid/config.yml` | Пример конфигурации собственного репозитория. Реальные пароли в репозиторий не попадают. |
| `.github/workflows/fdroid.yml` | Сборка store-варианта и публикация индекса в ветку `gh-pages`. |

Store-сборка отличается от обычной двумя вещами: `--dart-define=FDROID_BUILD=true`
скрывает встроенный автоапдейтер, а разрешение `REQUEST_INSTALL_PACKAGES`
удаляется из манифеста перед сборкой. Без этого F-Droid отклоняет приложение:
оно не должно устанавливать APK в обход магазина.

## Вариант A: собственный репозиторий

Репозиторий будет доступен по адресу
`https://imsudoer.github.io/mangaloader/fdroid/repo`. Клиент F-Droid проверяет
подпись индекса, поэтому обновления приходят автоматически, как из основного
магазина.

### 1. Создать ключ репозитория

Для этого репозитория ключ уже создан, секреты добавлены, резервная копия лежит у
владельца. Раздел нужен только при переезде на другой аккаунт или для форка:
новый ключ ломает обновления у тех, кто уже добавил репозиторий.

Ключ подписывает индекс, а не APK. Он создаётся один раз, хранится в секрете и
никогда не меняется: при смене ключа всем пользователям придётся заново добавлять
репозиторий.

```bash
keytool -genkeypair -v \
  -keystore fdroid-repo.jks \
  -alias fdroid \
  -keyalg RSA -keysize 4096 -validity 36500 \
  -storepass 'ДЛИННЫЙ_ПАРОЛЬ' \
  -keypass 'ДЛИННЫЙ_ПАРОЛЬ' \
  -dname "CN=Manga Loader F-Droid Repo, O=imsudoer, C=RU"
```

Base64 для секрета:

```bash
base64 -w 0 fdroid-repo.jks
```

Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("fdroid-repo.jks"))
```

Сделайте резервную копию `fdroid-repo.jks` и пароля. Восстановить их из GitHub
нельзя.

### 2. Добавить секреты

`Settings → Secrets and variables → Actions`:

| Секрет | Значение |
| :--- | :--- |
| `FDROID_REPO_KEYSTORE_BASE64` | Содержимое `fdroid-repo.jks` в base64. |
| `FDROID_REPO_STORE_PASSWORD` | Пароль хранилища. |
| `FDROID_REPO_KEY_PASSWORD` | Пароль ключа. |
| `FDROID_REPO_KEY_ALIAS` | `fdroid`. |
| `RELEASE_KEYSTORE_BASE64` | Ключ, которым подписаны GitHub-релизы. Обязателен. |
| `RELEASE_KEYSTORE_PASSWORD` | Пароль релизного ключа. |
| `RELEASE_KEY_PASSWORD` | Пароль ключа релиза. |
| `RELEASE_KEY_ALIAS` | Алиас релизного ключа. |

APK обязан быть подписан тем же ключом, что и GitHub-релизы. Иначе установленное
приложение не сможет обновиться: Android отказывает при смене подписи.

В этом репозитории все четыре секрета `FDROID_REPO_*` уже созданы, повторно
генерировать ключ не нужно. `RELEASE_KEYSTORE_BASE64` хранится с августа 2026 и
подписывает релизы сертификатом `E2:01:54:EA:…:82:BE`. Прочитать значение
секрета нельзя даже владельцу репозитория: workflow получает его сам. Резервные
копии обоих ключей (`.jks` и пароли) хранятся у владельца вне репозитория; без
них восстановить подпись невозможно.

Проверить состав секретов:

```bash
gh secret list -R imsudoer/mangaloader
```

### 3. Включить Pages

В репозитории это уже сделано: источник — ветка `gh-pages`, папка `/ (root)`,
сайт `https://imsudoer.github.io/mangaloader/`.

Если настраиваете форк: `Settings → Pages → Build and deployment`:

- Source: **Deploy from a branch**
- Branch: **gh-pages**, папка **/ (root)**

Ветку создаст первый запуск workflow.

### 4. Опубликовать

Workflow `Publish F-Droid repo` запускается на пуш стабильного тега `vX.Y.Z`
или вручную (`Run workflow`, тег в поле ввода). Бета-теги он отклоняет: они
остаются в GitHub Releases. Workflow собирает три APK по ABI, раскладывает их в
репозиторий, пересобирает индекс и пушит результат в `gh-pages`.

Проверка после запуска:

```bash
curl -sI https://imsudoer.github.io/mangaloader/fdroid/repo/index-v2.json
curl -s  https://imsudoer.github.io/mangaloader/fdroid/index.html
```

Страница `https://imsudoer.github.io/mangaloader/fdroid/` содержит ссылку
`fdroidrepos://` с отпечатком ключа: по ней репозиторий добавляется в клиент одним
нажатием.

### 5. Локальная проверка индекса

```bash
python -m pip install fdroidserver
mkdir -p /tmp/fdroid-check/repo /tmp/fdroid-check/metadata
cd /tmp/fdroid-check

keytool -genkeypair -keystore test.jks -alias fdroid -keyalg RSA -keysize 2048 \
  -validity 365 -storepass testpass -keypass testpass -dname "CN=Test"

printf '%s\n' \
  'repo_url: https://example.com/fdroid/repo' \
  'repo_name: Manga Loader' \
  'archive_older: 0' \
  'keystore: test.jks' \
  'repo_keyalias: fdroid' \
  'keystorepass: testpass' \
  'keypass: testpass' > config.yml

mkdir -p metadata/bshv.mangaloader.app
cp -R <repo>/fastlane/metadata/android/en-US metadata/bshv.mangaloader.app/
cp <repo>/build/app/outputs/flutter-apk/*.apk repo/
fdroid update --create-metadata
```

Индекс появится в `repo/index-v1.jar` и `repo/index-v2.json`; подпись проверяется
командой `apksigner verify --print-certs repo/index-v1.jar`.

## Вариант B: основной репозиторий F-Droid

Порядок: сначала RFP, потом merge request. Без RFP ревьюеры могут закрыть MR как
дубликат.

1. Создайте issue в [gitlab.com/fdroid/rfp](https://gitlab.com/fdroid/rfp/-/issues)
   по шаблону: название, ссылка на исходники, лицензия, описание, чем приложение
   отличается от существующих читалок.
2. Сделайте форк [gitlab.com/fdroid/fdroiddata](https://gitlab.com/fdroid/fdroiddata)
   и скопируйте `fdroid/bshv.mangaloader.app.yml` в
   `metadata/bshv.mangaloader.app.yml`.
3. Проверьте метаданные:

   ```bash
   fdroid lint bshv.mangaloader.app
   fdroid rewritemeta bshv.mangaloader.app
   ```

4. Запустите сборку в чистом окружении, если есть Docker:

   ```bash
   fdroid build -v bshv.mangaloader.app:72
   ```

5. Откройте MR. В описании укажите, что приложение не использует проприетарные
   SDK и не содержит рекламы, и что `NonFreeNet` уже объявлен.

Что проверяют ревьюеры в этом проекте:

- `REQUEST_INSTALL_PACKAGES` удалён, автоапдейтер отключён флагом `FDROID_BUILD`.
- Сборка не тянет проприетарные зависимости. Flutter SDK и Rust toolchain
  разрешены политикой; `rustup` ставится из Debian, потому что `rustc` из Debian
  не содержит std для Android-целей.
- Версия и `versionCode` в `pubspec.yaml`, `fastlane/.../changelogs/<code>.txt` и
  метаданных совпадают.
- APK собирается без `android/local.properties` и без предварительно собранных
  `.so`.

Реалистичное ожидание: приложение является клиентом MangaLib, а политика F-Droid
запрещает приложения, нарушающие права третьих лиц. Отказ вероятен на этапе
ручной проверки, даже если сборка проходит. Собственный репозиторий от этого не
зависит и работает сразу.

Ещё одно следствие: в основном репозитории APK подписывается ключом F-Droid.
Пользователь не сможет обновиться с GitHub-сборки на F-Droid-сборку без удаления
приложения.

### Текст для RFP

```text
App: Manga Loader
Source: https://github.com/imsudoer/mangaloader
License: GPL-3.0-only
Category: Reading

An unofficial MangaLib client: vertical webtoon and paged reader, CBZ downloads
handled by a Rust engine, library sync, reading statistics, desktop builds for
Windows and Linux.

No ads, analytics, crash reporting or proprietary SDKs. Flutter UI, Rust core via
flutter_rust_bridge. Store builds disable the in-app updater and drop
REQUEST_INSTALL_PACKAGES; updates are left to F-Droid.

The app depends on the proprietary MangaLib service, which is declared as the
NonFreeNet anti-feature.
```

### Текст для merge request

```text
Problem
-------
Manga Loader is not in fdroiddata. The app ships its own APK updater and requests
REQUEST_INSTALL_PACKAGES, both of which are not acceptable for a store build.

Key changes
-----------
- Add metadata/bshv.mangaloader.app.yml with a Flutter + Rust build recipe.
- Flutter comes from the flutter srclib, Rust from Debian rustup because Debian
  rustc has no std for Android targets.
- The build drops REQUEST_INSTALL_PACKAGES and passes FDROID_BUILD=true, which
  hides the updater in the UI.
- NonFreeNet is declared for the MangaLib dependency.

Verification
------------
- fdroid lint bshv.mangaloader.app
- fdroid build -v bshv.mangaloader.app:72
```

## Новая версия

1. Поднимите `version` в `pubspec.yaml` (`1.9.9+73`).
2. Добавьте `fastlane/metadata/android/{en-US,ru-RU}/changelogs/73.txt`.
3. Обновите `fdroid/bshv.mangaloader.app.yml`: `versionName`, `versionCode`,
   `commit` (полный SHA тега), `CurrentVersion`, `CurrentVersionCode`.
4. Запушьте тег `v1.9.9`. Workflow сам соберёт и опубликует репозиторий.

## Ограничения

- Репозиторий хранит APK только текущей версии: `archive_older: 0`. Старые
  версии удаляются при обновлении индекса.
- `fdroidserver` собирает индекс на раннере GitHub, ключ репозитория живёт в
  секретах. Это компромисс: для параноидального сценария индекс подписывают на
  отдельной машине, а на сервер выкладывают готовый результат.
- F-Droid не поддерживает обновление приложения, установленного из другого
  источника с другой подписью. Это ограничение Android, а не магазина.

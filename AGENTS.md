# Manga Loader: Agent Working Rules

These rules apply to every agent and every chat working in this repository.
The global rules in `C:\Users\Andre\.config\opencode\antigravity_instructions.md`
also apply. This file adds project specifics and overrides any generic commit
or release convention that conflicts with it.

## Git

- Commit messages are plain, 3-8 lowercase words in imperative mood, with no
  period at the end.
  - No Conventional Commit prefixes: `feat:`, `fix:`, `chore:`, `refactor:`,
    `build:`, `ci:`, and similar are forbidden.
  - No emojis, no corporate buzzwords, no vague one-word messages.
  - Examples: `fix reader page counter`, `add glass scrollbars to long lists`.
- One logical change per commit. Stage only the files that belong to that
  change. Do not use a blind `git add -A`.
- Never commit:
  - scratch files or temporary tests;
  - `design/` drafts, screenshots, or generated icon concepts;
  - build output, `.dart_tool`, `build/`, or IDE files;
  - generated plugin registrant files;
  - local environment files or credentials.
- Do not rewrite, amend, rebase, or force-push published commits or tags
  without explicit user approval. Fix a bad published message in a new commit
  or ask first.
- PR and push summaries use three blocks: problem and context, key changes,
  verification. No file-by-file laundry lists.

## Releases and versions

- Stable releases only when the user explicitly asks for a stable release.
  Otherwise ship a beta tag `vX.Y.Z-beta.N` as a GitHub prerelease.
- Stable and beta tags are separate. Never retag, move, or delete a published
  tag without explicit approval.
- The build number in `pubspec.yaml` (`+N`) must strictly increase.
- Beta tags must not be submitted to RuStore.
- RuStore builds filter blocked titles, omit `REQUEST_INSTALL_PACKAGES`, and
  package arm64 only.
- Keep the current app icon (`assets/icon_monet.png`). Do not replace it unless
  the user asks.

## Code

- Read the existing architecture, naming, and dependencies before changing
  anything. Fix root causes, not symptoms.
- Deliver complete, compile-ready code. No stubs, `TODO` placeholders,
  truncated functions, or pseudo-code.
- Keep types precise. Avoid `any`, unchecked casts, and speculative
  abstractions.
- Handle loading, empty, error, edge cases, keyboard/focus, and accessibility
  in every user-facing flow.
- Comments are reserved for non-obvious WHY: domain constraints, OS quirks,
  workarounds, invariants. No syntax narration, decorative separators,
  redundant docstrings, or AI meta-comments.
- No emojis in UI, code, commits, or docs.
- Every user-facing string is localized RU/EN under `lib/l10n/strings/`.
  Do not hardcode UI text.

## Tests and cleanliness

- The approved test set is:
  - `test/version_compare_test.dart`
  - `test/content_filter_test.dart`
  - `test/content_filter_coverage_test.dart`
  - `test/title_match_test.dart`
- Do not add new test files unless the user explicitly approves them.
  `test/desktop_layout_test.dart` was added during the desktop review without
  approval; keep it only if the user confirms, otherwise remove it separately.
  Temporary verification tests must be deleted before committing.
- Do not create scratch scripts in the repository. Use the system temp
  directory for one-off probes.

## Reader-specific rule

`lib/pages/reader_page.dart` is the most sensitive file in the project. Do not
change its reading logic, page geometry, zoom, or persistence as a side effect
of an unrelated task. Reader changes need an explicit scope and verification on
a real device or a focused widget test.

## Verification

Run before reporting completion:

```powershell
flutter analyze lib
flutter test
```

Rust changes also require:

```powershell
cd rust
cargo test --lib
```

Android verification uses CI artifacts and ADB. Local Android builds require
SDK licenses and are not expected to run on this machine.
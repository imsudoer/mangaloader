import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Single gate for desktop-only chrome. The mobile tree keeps its original
/// widget hierarchy, because every desktop branch is checked against this.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get isMacPlatform => !kIsWeb && Platform.isMacOS;

/// Modifier key label used by shortcut hints. Windows/Linux use Ctrl, macOS Cmd.
String get desktopModifierLabel => isMacPlatform ? '\u2318' : 'Ctrl';

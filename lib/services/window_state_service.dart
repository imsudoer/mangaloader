import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

/// Remembers the desktop window size and position between launches.
class WindowStateService {
  static const String _storageKey = 'window_geometry';

  static Timer? _debounce;
  static bool _tracking = false;

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<void> restore() async {
    if (!_isDesktop) return;
    try {
      final raw = await rust_storage.getSetting(key: _storageKey);
      if (raw == null || raw.isEmpty) return;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final width = (json['width'] as num?)?.toDouble();
      final height = (json['height'] as num?)?.toDouble();
      final x = (json['x'] as num?)?.toDouble();
      final y = (json['y'] as num?)?.toDouble();

      if (width != null && height != null) {
        await windowManager.setSize(_sanitizeSize(Size(width, height)));
      }
      if (x != null && y != null) {
        final position = _sanitizePosition(Offset(x, y));
        if (position != null) {
          await windowManager.setPosition(position);
        }
      }
      if (json['maximized'] == true) {
        await windowManager.maximize();
      }
    } catch (_) {
      // A corrupt or out-of-date payload must never block startup.
    }
  }

  /// Starts debounced persistence of resize and move events.
  static void startTracking() {
    if (!_isDesktop || _tracking) return;
    _tracking = true;
    windowManager.addListener(_DesktopWindowListener());
  }

  static void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  static Future<void> _save() async {
    if (!_isDesktop) return;
    try {
      final maximized = await windowManager.isMaximized();
      if (maximized) {
        // Store the restore size so un-maximizing later still has sane bounds.
        final previous = await _readStored();
        await _write({...previous, 'maximized': true});
        return;
      }

      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await _write({
        'width': size.width,
        'height': size.height,
        'x': position.dx,
        'y': position.dy,
        'maximized': false,
      });
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _readStored() async {
    try {
      final raw = await rust_storage.getSetting(key: _storageKey);
      if (raw == null || raw.isEmpty) return const {};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    await rust_storage.setSetting(key: _storageKey, value: jsonEncode(data));
  }

  static Size _sanitizeSize(Size size) {
    final width = size.width.clamp(600.0, 10000.0);
    final height = size.height.clamp(480.0, 10000.0);
    return Size(width, height);
  }

  /// Rejects positions that could not belong to any connected display, so a window
  /// saved on a disconnected monitor does not open completely off-screen.
  static Offset? _sanitizePosition(Offset position) {
    if (!position.dx.isFinite || !position.dy.isFinite) return null;
    const limit = 10000.0;
    if (position.dx.abs() > limit || position.dy.abs() > limit) return null;
    return position;
  }

  static Size get defaultSize => const Size(1200, 800);
}

class _DesktopWindowListener extends WindowListener {
  @override
  void onWindowResized() => WindowStateService._scheduleSave();

  @override
  void onWindowMoved() => WindowStateService._scheduleSave();

  @override
  void onWindowMaximize() => WindowStateService._scheduleSave();

  @override
  void onWindowUnmaximize() => WindowStateService._scheduleSave();
}
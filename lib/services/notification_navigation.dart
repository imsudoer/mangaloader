import 'package:go_router/go_router.dart';

/// Translates a local notification payload into navigation.
///
/// The notification plugin delivers taps on the platform thread, outside any widget
/// tree, so the GoRouter instance is registered from [main] and driven directly.
class NotificationNavigation {
  static GoRouter? _router;

  /// Payload sent for "an app update is available".
  static const String updatePayload = 'update';

  /// Payload sent for the daily streak reminder.
  static const String streakPayload = 'streak';

  /// Payload prefix for a released chapter: `chapter:<slugUrl>`.
  static const String chapterPrefix = 'chapter:';

  static void attachRouter(GoRouter router) {
    _router = router;
  }

  static void handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final router = _router;
    if (router == null) return;

    if (payload == updatePayload) {
      router.go('/settings');
      return;
    }

    if (payload == streakPayload) {
      router.go('/statistics');
      return;
    }

    if (payload.startsWith(chapterPrefix)) {
      final slugUrl = payload.substring(chapterPrefix.length).trim();
      if (slugUrl.isNotEmpty) router.go('/manga/$slugUrl');
    }
  }
}
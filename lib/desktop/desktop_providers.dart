import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented by the shell to move keyboard focus into the catalog search
/// field. A counter instead of a bool keeps repeated Ctrl+K presses working.
final desktopSearchFocusProvider = StateProvider<int>((ref) => 0);

/// Incremented by the shell on F5/Ctrl+R. Pages listen and reload their data
/// while keeping scroll position and filters intact.
final desktopRefreshProvider = StateProvider<int>((ref) => 0);

/// Persisted across route changes so the rail keeps the width the user chose.
final desktopRailCollapsedProvider = StateProvider<bool>((ref) => false);

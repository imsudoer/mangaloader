import 'package:flutter/widgets.dart';

/// Width budget shared by every desktop surface: the navigation rail, page
/// gutters, and the maximum column count for title grids.
class DesktopLayout {
  const DesktopLayout._();

  static const double railWidth = 244;
  static const double railCompactWidth = 68;
  static const double railLabelBreakpoint = 1000;

  static const double pageMaxWidth = 1680;
  static const double tableMaxWidth = 1320;
  static const double formMaxWidth = 1120;

  static const double gridGap = 14;
  static const double gridTileMinWidth = 176;

  static const double detailsSidebarWidth = 404;

  static int gridColumns(
    double width, {
    double minTileWidth = gridTileMinWidth,
    double gap = gridGap,
    int min = 2,
    int max = 12,
  }) {
    if (!width.isFinite || width <= 0) return min;
    final columns = ((width + gap) / (minTileWidth + gap)).floor();
    return columns.clamp(min, max);
  }

  static SliverGridDelegate tileDelegate({
    double maxTileWidth = 196,
    double gap = gridGap,
    double aspectRatio = 0.65,
  }) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxTileWidth,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      childAspectRatio: aspectRatio,
    );
  }
}

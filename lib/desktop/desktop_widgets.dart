import 'package:flutter/material.dart';
import 'package:mangaloader/desktop/desktop_layout.dart';
import 'package:mangaloader/desktop/desktop_platform.dart';
import 'package:mangaloader/theme/app_tokens.dart';

/// Applies the desktop content cap only on desktop. Mobile and tablet builds
/// receive the original child unchanged.
class DesktopWidthLimit extends StatelessWidget {
  const DesktopWidthLimit({
    super.key,
    required this.child,
    this.maxWidth = DesktopLayout.pageMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Row-level hover state and native context-menu handling. The builder receives
/// the hover flag so each page can choose its own surface treatment.
class DesktopHoverSurface extends StatefulWidget {
  const DesktopHoverSurface({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapDown,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final MouseCursor cursor;

  @override
  State<DesktopHoverSurface> createState() => _DesktopHoverSurfaceState();
}

class _DesktopHoverSurfaceState extends State<DesktopHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      child: MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.builder(context, _hovered),
      ),
    );
  }
}

/// Opens a menu at the pointer position instead of anchoring it to a button.
Future<T?> showDesktopMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future<T?>.value();
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    color: AppTokens.surfaceRaised,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      side: const BorderSide(color: AppTokens.borderStrong),
    ),
    items: items,
  );
}

PopupMenuItem<T> desktopMenuItem<T>({
  required T value,
  required IconData icon,
  required String label,
  bool destructive = false,
}) {
  final color = destructive ? Colors.redAccent : AppTokens.textPrimary;
  return PopupMenuItem<T>(
    value: value,
    height: 40,
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Column caption used by the downloads and history tables.
class DesktopTableHeader extends StatelessWidget {
  const DesktopTableHeader({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppTokens.surfaceDeep,
        border: Border(bottom: BorderSide(color: AppTokens.border, width: 1)),
      ),
      child: Row(children: children),
    );
  }
}

class DesktopTableHeaderCell extends StatelessWidget {
  const DesktopTableHeaderCell({
    super.key,
    required this.label,
    this.flex,
  });

  final String label;
  final int? flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex ?? 1,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTokens.textSecondary,
        ),
      ),
    );
  }
}

/// Compact key cap used by the rail footer and tooltips.
class DesktopKeyHint extends StatelessWidget {
  const DesktopKeyHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTokens.surfaceCard,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTokens.borderStrong, width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppTokens.textSecondary,
          height: 1.1,
        ),
      ),
    );
  }
}

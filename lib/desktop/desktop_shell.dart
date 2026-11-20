import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'package:mangaloader/desktop/desktop_layout.dart';
import 'package:mangaloader/desktop/desktop_platform.dart';
import 'package:mangaloader/desktop/desktop_providers.dart';
import 'package:mangaloader/desktop/desktop_widgets.dart';
import 'package:mangaloader/l10n/strings/desktop_strings.dart';
import 'package:mangaloader/l10n/strings/shell_strings.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:mangaloader/widgets/offline_banner.dart';

/// Desktop application frame: persistent navigation rail, keyboard shortcuts
/// and window title. The routed page is rendered untouched on the right.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  @override
  void initState() {
    super.initState();
    _scheduleTitle();
  }

  @override
  void didUpdateWidget(covariant DesktopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _scheduleTitle();
  }

  void _scheduleTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Details and the reader own their window title because they know the
      // current title and chapter; the shell must not overwrite them.
      if (widget.location.startsWith('/manga/') ||
          widget.location.startsWith('/read')) {
        return;
      }
      final section = _sectionLabel(widget.location);
      windowManager
          .setTitle(
              section.isEmpty ? 'Manga Loader' : 'Manga Loader - $section')
          .catchError((Object _) {});
    });
  }

  String _sectionLabel(String location) {
    final s = ShellStrings.of(context);
    if (location.startsWith('/search')) return s.catalog;
    if (location.startsWith('/library')) return s.library;
    if (location.startsWith('/downloads')) return s.downloads;
    if (location.startsWith('/history')) return s.history;
    if (location.startsWith('/achievements')) return s.achievements;
    if (location.startsWith('/statistics')) return s.statistics;
    if (location.startsWith('/profile')) return s.profile;
    if (location.startsWith('/settings')) return s.settings;
    return s.home;
  }

  void _openSearch() {
    if (!widget.location.startsWith('/search')) {
      context.go('/search');
    }
    ref.read(desktopSearchFocusProvider.notifier).state++;
  }

  void _goBack() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  void _refresh() {
    ref.read(desktopRefreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(desktopRailCollapsedProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _goBack,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            _goBack,
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _refresh,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _refresh,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wideEnough = constraints.maxWidth >=
                        DesktopLayout.railLabelBreakpoint;
                    final expanded = wideEnough && !collapsed;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DesktopRail(
                          location: widget.location,
                          expanded: expanded,
                          showToggle: wideEnough,
                          onToggle: () => ref
                              .read(desktopRailCollapsedProvider.notifier)
                              .state = !collapsed,
                          onSearch: _openSearch,
                          onRefresh: _refresh,
                          onNavigate: (route) => context.go(route),
                        ),
                        Expanded(child: widget.child),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.location,
    required this.expanded,
    required this.showToggle,
    required this.onToggle,
    required this.onSearch,
    required this.onRefresh,
    required this.onNavigate,
  });

  final String location;
  final bool expanded;
  final bool showToggle;
  final VoidCallback onToggle;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final ValueChanged<String> onNavigate;

  bool _selected(String route) {
    if (route == '/') return location == '/' || location.isEmpty;
    return location == route || location.startsWith('$route/');
  }

  void _moveFocus(bool forward) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return;
    forward ? node.nextFocus() : node.previousFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesktopStrings.of(context);
    final shell = ShellStrings.of(context);
    final width =
        expanded ? DesktopLayout.railWidth : DesktopLayout.railCompactWidth;

    return AnimatedContainer(
      duration: AppTokens.normal,
      curve: Curves.easeOutCubic,
      width: width,
      decoration: const BoxDecoration(
        color: AppTokens.surfaceDeep,
        border: Border(right: BorderSide(color: AppTokens.border, width: 1)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, s),
            Padding(
              padding: EdgeInsets.fromLTRB(
                expanded ? 12 : 10,
                4,
                expanded ? 12 : 10,
                8,
              ),
              child: _DesktopSearchButton(
                expanded: expanded,
                onTap: onSearch,
              ),
            ),
            const Divider(height: 1, color: AppTokens.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _moveFocus(true),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _moveFocus(false),
                  },
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NavSection(
                          title: shell.sectionBrowse,
                          expanded: expanded,
                          children: [
                            _DesktopNavItem(
                              label: shell.home,
                              icon: Icons.home_outlined,
                              selectedIcon: Icons.home_rounded,
                              selected: _selected('/'),
                              expanded: expanded,
                              onTap: () => onNavigate('/'),
                            ),
                            _DesktopNavItem(
                              label: shell.catalog,
                              icon: Icons.explore_outlined,
                              selectedIcon: Icons.explore_rounded,
                              selected: _selected('/search'),
                              expanded: expanded,
                              onTap: () => onNavigate('/search'),
                            ),
                            _DesktopNavItem(
                              label: shell.library,
                              icon: Icons.collections_bookmark_outlined,
                              selectedIcon: Icons.collections_bookmark_rounded,
                              selected: _selected('/library'),
                              expanded: expanded,
                              onTap: () => onNavigate('/library'),
                            ),
                            _DesktopNavItem(
                              label: shell.downloads,
                              icon: Icons.download_outlined,
                              selectedIcon: Icons.download_rounded,
                              selected: _selected('/downloads'),
                              expanded: expanded,
                              onTap: () => onNavigate('/downloads'),
                            ),
                            _DesktopNavItem(
                              label: shell.history,
                              icon: Icons.history_rounded,
                              selectedIcon: Icons.history_toggle_off_rounded,
                              selected: _selected('/history'),
                              expanded: expanded,
                              onTap: () => onNavigate('/history'),
                            ),
                          ],
                        ),
                        _NavSection(
                          title: shell.sectionInsights,
                          expanded: expanded,
                          children: [
                            _DesktopNavItem(
                              label: shell.achievements,
                              icon: Icons.emoji_events_outlined,
                              selectedIcon: Icons.emoji_events_rounded,
                              selected: _selected('/achievements'),
                              expanded: expanded,
                              onTap: () => onNavigate('/achievements'),
                            ),
                            _DesktopNavItem(
                              label: shell.statistics,
                              icon: Icons.insights_outlined,
                              selectedIcon: Icons.insights_rounded,
                              selected: _selected('/statistics'),
                              expanded: expanded,
                              onTap: () => onNavigate('/statistics'),
                            ),
                          ],
                        ),
                        _NavSection(
                          title: shell.sectionAccount,
                          expanded: expanded,
                          children: [
                            _DesktopNavItem(
                              label: shell.profile,
                              icon: Icons.person_outline_rounded,
                              selectedIcon: Icons.person_rounded,
                              selected: _selected('/profile'),
                              expanded: expanded,
                              onTap: () => onNavigate('/profile'),
                            ),
                            _DesktopNavItem(
                              label: shell.settings,
                              icon: Icons.settings_outlined,
                              selectedIcon: Icons.settings_rounded,
                              selected: _selected('/settings'),
                              expanded: expanded,
                              onTap: () => onNavigate('/settings'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppTokens.border),
            _buildFooter(context, s),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DesktopStrings s) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Tooltip(
            message: s.brand,
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onNavigate('/'),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTokens.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Manga Loader',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (expanded)
            IconButton(
              tooltip: s.collapseRail,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.keyboard_double_arrow_left_rounded,
                size: 19,
                color: AppTokens.textSecondary,
              ),
              onPressed: onToggle,
            )
          else
            const SizedBox(width: 8),
          if (expanded) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, DesktopStrings s) {
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            if (showToggle)
              IconButton(
                tooltip: s.expandRail,
                icon: const Icon(
                  Icons.keyboard_double_arrow_right_rounded,
                  size: 19,
                  color: AppTokens.textSecondary,
                ),
                onPressed: onToggle,
              ),
            IconButton(
              tooltip: '${s.refresh} (F5)',
              icon: const Icon(
                Icons.refresh_rounded,
                size: 19,
                color: AppTokens.textSecondary,
              ),
              onPressed: onRefresh,
            ),
          ],
        ),
      );
    }

    final modifier = desktopModifierLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.keyboardHint,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 7),
          _ShortcutRow(
            keys: '$modifier K',
            label: s.shortcutSearch,
          ),
          const SizedBox(height: 4),
          _ShortcutRow(
            keys: 'Alt \u2190',
            label: s.shortcutBack,
          ),
          const SizedBox(height: 4),
          _ShortcutRow(keys: 'F5', label: s.shortcutRefresh),
        ],
      ),
    );
  }
}

class _DesktopSearchButton extends StatefulWidget {
  const _DesktopSearchButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_DesktopSearchButton> createState() => _DesktopSearchButtonState();
}

class _DesktopSearchButtonState extends State<_DesktopSearchButton> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesktopStrings.of(context);
    final modifier = desktopModifierLabel;
    final expanded = widget.expanded;

    final body = AnimatedContainer(
      duration: AppTokens.fast,
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 0),
      decoration: BoxDecoration(
        color: _hovered ? AppTokens.surfaceCard : AppTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: _focused
              ? Theme.of(context).colorScheme.primary
              : AppTokens.borderStrong,
          width: _focused ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment:
            expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_rounded,
            size: 17,
            color: AppTokens.textSecondary,
          ),
          if (expanded) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.searchPlaceholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
            DesktopKeyHint(label: '$modifier K'),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      label: s.searchPlaceholder,
      child: Tooltip(
        message: '${s.searchTooltip} ($modifier K)',
        waitDuration: const Duration(milliseconds: 500),
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) {
            if (value != _hovered) setState(() => _hovered = value);
          },
          onShowFocusHighlight: (value) {
            if (value != _focused) setState(() => _focused = value);
          },
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: _activate,
            behavior: HitTestBehavior.opaque,
            child: body,
          ),
        ),
      ),
    );
  }
}

class _NavSection extends StatelessWidget {
  const _NavSection({
    required this.title,
    required this.expanded,
    required this.children,
  });

  final String title;
  final bool expanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: AppTokens.textSecondary,
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Divider(height: 1, color: AppTokens.border),
          ),
        ...children,
      ],
    );
  }
}

class _DesktopNavItem extends StatefulWidget {
  const _DesktopNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final foreground = selected ? Colors.white : AppTokens.textSecondary;
    final background = selected
        ? AppTokens.accent.withValues(alpha: 0.16)
        : (_hovered
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.transparent);

    final content = AnimatedContainer(
      duration: AppTokens.fast,
      curve: Curves.easeOutCubic,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: _focused
              ? Theme.of(context).colorScheme.primary
              : (selected
                  ? AppTokens.accent.withValues(alpha: 0.45)
                  : Colors.transparent),
          width: 1.2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Positioned(
              left: 0,
              top: 10,
              bottom: 10,
              child: Container(
                width: 2.5,
                decoration: BoxDecoration(
                  color: AppTokens.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          if (widget.expanded)
            Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  selected ? widget.selectedIcon : widget.icon,
                  size: 18,
                  color: foreground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            )
          else
            Icon(
              selected ? widget.selectedIcon : widget.icon,
              size: 19,
              color: foreground,
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 600),
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) {
            if (value != _hovered) setState(() => _hovered = value);
          },
          onShowFocusHighlight: (value) {
            if (value != _focused) setState(() => _focused = value);
          },
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: _activate,
            behavior: HitTestBehavior.opaque,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DesktopKeyHint(label: keys),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary),
          ),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dynamic_color/dynamic_color.dart' show DynamicColorBuilder;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/frb_generated.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/library_page.dart';
import 'pages/downloads_page.dart';
import 'pages/profile_page.dart';
import 'pages/settings_page.dart';
import 'pages/manga_details_page.dart';
import 'pages/reader_page.dart';
import 'pages/login_webview_page.dart';
import 'pages/achievements_page.dart';
import 'pages/statistics_page.dart';
import 'pages/history_page.dart';
import 'widgets/offline_banner.dart';
import 'widgets/manga_card.dart' show CoverHeroScope;
import 'l10n/strings/shell_strings.dart';
import 'providers/settings_provider.dart';

import 'services/streak_notification_service.dart';
import 'services/chapter_tracker_service.dart';
import 'services/download_queue_service.dart';
import 'services/achievement_events.dart';
import 'services/notification_navigation.dart';
import 'services/window_state_service.dart';
import 'package:mangaloader/theme/app_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  // Initialize database first: the saved window geometry lives in the settings table.
  final appDir = await getApplicationDocumentsDirectory();
  await rust_storage.initDatabase(appDir: appDir.path);

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(450, 600),
      center: true,
      title: "Manga Loader",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Restore before showing so the saved bounds win over the centered defaults.
      await WindowStateService.restore();
      await windowManager.show();
      await windowManager.focus();
      WindowStateService.startTracking();
    });
  }

  // Initialize Streak Push Notifications
  await StreakNotificationService.init();
  await StreakNotificationService.scheduleDailyStreakReminder();

  // Initialize Background Sync (Workmanager on Android)
  await ChapterTrackerService.initBackgroundWork();

  NotificationNavigation.attachRouter(_router);

  runApp(const ProviderScope(child: MangaLoaderApp()));
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class MangaLoaderApp extends ConsumerStatefulWidget {
  const MangaLoaderApp({super.key});

  @override
  ConsumerState<MangaLoaderApp> createState() => _MangaLoaderAppState();
}

class _MangaLoaderAppState extends ConsumerState<MangaLoaderApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadPersistentSettings(ref);
      final events = AchievementEvents.instance;
      await events.ensureLoaded();
      events.increment('app_opens');
      events.addToSet('app_days', achievementDayKey(DateTime.now()));
      // Re-schedule with the language the user actually configured; the early call in
      // main() runs before preferences are read from the database.
      await StreakNotificationService.scheduleDailyStreakReminder(
        isRu: ref.read(localeProvider)?.languageCode != 'en',
      );
      // Resume downloads that were interrupted by the previous app shutdown.
      await DownloadQueueService.instance.restoreAndResume(ref);
      ChapterTrackerService.checkLibraryUpdates(ref);
      ChapterTrackerService.startForegroundPeriodicTracking(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isAmoled = ref.watch(amoledModeProvider);
    final locale = ref.watch(localeProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme lightColorScheme = lightDynamic ?? AppTheme.lightTheme.colorScheme;
        final ColorScheme darkColorScheme = isAmoled
            ? AppTheme.amoledTheme.colorScheme
            : (darkDynamic ?? AppTheme.darkTheme.colorScheme);

        final ThemeData darkThemeToUse = (isAmoled ? AppTheme.amoledTheme : AppTheme.darkTheme).copyWith(
          colorScheme: darkColorScheme,
        );

        final ThemeData lightThemeToUse = AppTheme.lightTheme.copyWith(
          colorScheme: lightColorScheme,
        );

        final Widget app = MaterialApp.router(
          title: 'Manga Loader',
          theme: lightThemeToUse,
          darkTheme: darkThemeToUse,
          themeMode: themeMode,
          locale: locale,
          // Keeps the navigation stack when Android recreates the activity after
          // the user spends time in another app; without it the process restart
          // always lands on the home tab.
          restorationScopeId: 'manga-loader',
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ru'),
            Locale('en'),
          ],
          scrollBehavior: AppScrollBehavior(),
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
        );
        return app;
      },
    );
  }
}

final _router = GoRouter(
  restorationScopeId: 'manga-loader-router',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(child: HomePage()),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) => const NoTransitionPage(child: SearchPage()),
        ),
        GoRoute(
          path: '/library',
          pageBuilder: (context, state) => const NoTransitionPage(child: LibraryPage()),
        ),
        GoRoute(
          path: '/downloads',
          pageBuilder: (context, state) => const NoTransitionPage(child: DownloadsPage()),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => const NoTransitionPage(child: ProfilePage()),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SettingsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(animation),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const LoginWebviewPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(animation),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/achievements',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const AchievementsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(animation),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/history',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const HistoryPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(animation),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/statistics',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const StatisticsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(animation),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/manga/:slugUrl',
      pageBuilder: (context, state) {
        final slugUrl = state.pathParameters['slugUrl']!;
        return CustomTransitionPage(
          key: state.pageKey,
          child: MangaDetailsPage(slugUrl: slugUrl),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic))
                  .animate(animation),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: '/ru/manga/:slugUrl',
      redirect: (context, state) => '/manga/${state.pathParameters['slugUrl']}',
    ),
    GoRoute(
      path: '/ru/:slugUrl',
      redirect: (context, state) => '/manga/${state.pathParameters['slugUrl']}',
    ),
    GoRoute(
      path: '/read-local',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return CustomTransitionPage(
          key: state.pageKey,
          child: ReaderPage(
            slugUrl: '',
            volume: '1',
            number: '1',
            localCbzPath: filePath,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
      },
    ),
    GoRoute(
      path: '/read/:slugUrl/:volume/:number',
      pageBuilder: (context, state) {
        final branchIdStr = state.uri.queryParameters['branchId'];
        final branchId = branchIdStr != null ? int.tryParse(branchIdStr) : null;
        final pageStr = state.uri.queryParameters['page'];
        final initialPage = pageStr != null ? int.tryParse(pageStr) : null;
        return CustomTransitionPage(
          key: state.pageKey,
          child: ReaderPage(
            slugUrl: state.pathParameters['slugUrl']!,
            volume: state.pathParameters['volume']!,
            number: state.pathParameters['number']!,
            branchId: branchId,
            initialPageIndex: initialPage,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
      },
    ),
  ],
);

class AppShell extends StatefulWidget {
  /// Current router location. Tab selection is derived from it, so back,
  /// forward and deep links all land on the matching tab.
  final String location;

  const AppShell({super.key, required this.location});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<String> _tabRoutes = [
    '/',
    '/search',
    '/library',
    '/downloads',
    '/profile',
  ];

  /// Tab widgets are created on first visit and then kept alive by the
  /// IndexedStack, which is what preserves scroll offsets, loaded pages and
  /// active filters across tab switches. Mounting all five up front would fire
  /// five independent network loads at startup.
  final List<Widget?> _tabs = List<Widget?>.filled(_tabRoutes.length, null);

  int get _selectedIndex => _indexForLocation(widget.location);

  static int _indexForLocation(String location) {
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/library')) return 2;
    if (location.startsWith('/downloads')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  Widget _tabFor(int index) {
    return _tabs[index] ??= switch (index) {
      1 => const SearchPage(),
      2 => const LibraryPage(),
      3 => const DownloadsPage(),
      4 => const ProfilePage(),
      _ => const HomePage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = ShellStrings.of(context);
    final selectedIndex = _selectedIndex;

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              sizing: StackFit.expand,
              children: [
                for (var index = 0; index < _tabRoutes.length; index++)
                  // Hidden tabs stay mounted so their state survives, but they
                  // must not join the current Hero flight (duplicate cover tags
                  // would throw) and must not tick animations offscreen.
                  CoverHeroScope(
                    child: HeroMode(
                      enabled: index == selectedIndex,
                      child: TickerMode(
                        enabled: index == selectedIndex,
                        child: (_tabs[index] != null || index == selectedIndex)
                            ? _tabFor(index)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF171717), AppTokens.surfaceDeep],
          ),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const tabCount = 5;
                final cellWidth = constraints.maxWidth / tabCount;
                return Stack(
                  children: [
                    // One pill slides between equal cells, so the highlight is
                    // always exactly one fifth of the bar instead of hugging the
                    // selected label.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * cellWidth + 4,
                      width: cellWidth - 8,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTokens.accent.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTokens.accent.withValues(alpha: 0.42),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTokens.accent.withValues(alpha: 0.18),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _buildNavItem(
                          index: 0,
                          selectedIndex: selectedIndex,
                          label: s.home,
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home_rounded,
                          onTap: () => _navigateTo(0, '/'),
                        ),
                        _buildNavItem(
                          index: 1,
                          selectedIndex: selectedIndex,
                          label: s.catalog,
                          icon: Icons.explore_outlined,
                          selectedIcon: Icons.explore_rounded,
                          onTap: () => _navigateTo(1, '/search'),
                        ),
                        _buildNavItem(
                          index: 2,
                          selectedIndex: selectedIndex,
                          label: s.library,
                          icon: Icons.collections_bookmark_outlined,
                          selectedIcon: Icons.collections_bookmark_rounded,
                          onTap: () => _navigateTo(2, '/library'),
                        ),
                        _buildNavItem(
                          index: 3,
                          selectedIndex: selectedIndex,
                          label: s.downloads,
                          icon: Icons.download_outlined,
                          selectedIcon: Icons.download_rounded,
                          onTap: () => _navigateTo(3, '/downloads'),
                        ),
                        _buildNavItem(
                          index: 4,
                          selectedIndex: selectedIndex,
                          label: s.profile,
                          icon: Icons.person_outline_rounded,
                          selectedIcon: Icons.person_rounded,
                          onTap: () => _navigateTo(4, '/profile'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _navigateTo(int index, String route) {
    if (index == _selectedIndex) return;
    context.go(route);
  }

  Widget _buildNavItem({
    required int index,
    required int selectedIndex,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required VoidCallback onTap,
  }) {
    final isSelected = index == selectedIndex;
    final color = isSelected ? Colors.white : const Color(0xFF8E8E8E);

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    isSelected ? selectedIcon : icon,
                    size: 22,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                    letterSpacing: -0.1,
                    height: 1.1,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

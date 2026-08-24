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
import 'providers/settings_provider.dart';

import 'services/streak_notification_service.dart';
import 'services/chapter_tracker_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(450, 600),
      center: true,
      title: "Manga Loader",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize database
  final appDir = await getApplicationDocumentsDirectory();
  await rust_storage.initDatabase(appDir: appDir.path);

  // Initialize Streak Push Notifications
  await StreakNotificationService.init();
  await StreakNotificationService.scheduleDailyStreakReminder();

  // Initialize Background Sync (Workmanager on Android)
  await ChapterTrackerService.initBackgroundWork();

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
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
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
        return CustomTransitionPage(
          key: state.pageKey,
          child: ReaderPage(
            slugUrl: state.pathParameters['slugUrl']!,
            volume: state.pathParameters['volume']!,
            number: state.pathParameters['number']!,
            branchId: branchId,
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
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _previousIndex = 0;

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == '/') return 0;
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/library')) return 2;
    if (location.startsWith('/downloads')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final selectedIndex = _calculateSelectedIndex(context);
    final prevIndex = _previousIndex;
    if (selectedIndex != _previousIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _previousIndex = selectedIndex);
      });
    }

    final isForward = selectedIndex >= prevIndex;
    final beginOffset = isForward ? const Offset(0.20, 0.0) : const Offset(-0.20, 0.0);

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                final isCurrent = (child.key as ValueKey<int>?)?.value == selectedIndex;
                final slideTween = isCurrent
                    ? Tween<Offset>(begin: beginOffset, end: Offset.zero)
                    : Tween<Offset>(begin: Offset.zero, end: -beginOffset);

                return SlideTransition(
                  position: slideTween.animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOut,
                    ),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(selectedIndex),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF181818),
          border: Border(
            top: BorderSide(
              color: Color(0xFF2C2C2C),
              width: 0.8,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  selectedIndex: selectedIndex,
                  label: isRu ? 'Главная' : 'Home',
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  onTap: () => _navigateTo(0, '/'),
                ),
                _buildNavItem(
                  index: 1,
                  selectedIndex: selectedIndex,
                  label: isRu ? 'Каталог' : 'Catalog',
                  icon: Icons.explore_outlined,
                  selectedIcon: Icons.explore_rounded,
                  onTap: () => _navigateTo(1, '/search'),
                ),
                _buildNavItem(
                  index: 2,
                  selectedIndex: selectedIndex,
                  label: isRu ? 'Библиотека' : 'Library',
                  icon: Icons.collections_bookmark_outlined,
                  selectedIcon: Icons.collections_bookmark_rounded,
                  onTap: () => _navigateTo(2, '/library'),
                ),
                _buildNavItem(
                  index: 3,
                  selectedIndex: selectedIndex,
                  label: isRu ? 'Загрузки' : 'Downloads',
                  icon: Icons.download_outlined,
                  selectedIcon: Icons.download_rounded,
                  onTap: () => _navigateTo(3, '/downloads'),
                ),
                _buildNavItem(
                  index: 4,
                  selectedIndex: selectedIndex,
                  label: isRu ? 'Профиль' : 'Profile',
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  onTap: () => _navigateTo(4, '/profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateTo(int index, String route) {
    if (index == _previousIndex) return;
    setState(() {
      _previousIndex = index;
    });
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8A897C).withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.45), width: 1.0)
              : Border.all(color: Colors.transparent, width: 1.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              size: 22,
              color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

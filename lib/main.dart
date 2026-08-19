import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/frb_generated.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/library_page.dart';
import 'pages/downloads_page.dart';
import 'pages/settings_page.dart';
import 'pages/manga_details_page.dart';
import 'pages/reader_page.dart';
import 'pages/login_webview_page.dart';
import 'pages/achievements_page.dart';
import 'pages/statistics_page.dart';
import 'widgets/offline_banner.dart';
import 'providers/settings_provider.dart';

import 'services/streak_notification_service.dart';

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

class MangaLoaderApp extends ConsumerWidget {
  const MangaLoaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isAmoled = ref.watch(amoledModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Manga Loader',
      theme: AppTheme.lightTheme,
      darkTheme: isAmoled ? AppTheme.amoledTheme : AppTheme.darkTheme,
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
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(child: SettingsPage()),
        ),
      ],
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
    if (location.startsWith('/settings')) return 4;
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
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            if (index == selectedIndex) return;
            setState(() {
              _previousIndex = selectedIndex;
            });
            switch (index) {
              case 0:
                context.go('/');
                break;
              case 1:
                context.go('/search');
                break;
              case 2:
                context.go('/library');
                break;
              case 3:
                context.go('/downloads');
                break;
              case 4:
                context.go('/settings');
                break;
            }
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: isRu ? 'Главная' : 'Home',
            ),
            NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore_rounded),
              label: isRu ? 'Каталог' : 'Catalog',
            ),
            NavigationDestination(
              icon: const Icon(Icons.collections_bookmark_outlined),
              selectedIcon: const Icon(Icons.collections_bookmark_rounded),
              label: isRu ? 'Библиотека' : 'Library',
            ),
            NavigationDestination(
              icon: const Icon(Icons.download_outlined),
              selectedIcon: const Icon(Icons.download_rounded),
              label: isRu ? 'Загрузки' : 'Downloads',
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune_rounded),
              label: isRu ? 'Настройки' : 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

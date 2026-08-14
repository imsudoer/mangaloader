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
import 'providers/settings_provider.dart';

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
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchPage(),
        ),
        GoRoute(
          path: '/library',
          builder: (context, state) => const LibraryPage(),
        ),
        GoRoute(
          path: '/downloads',
          builder: (context, state) => const DownloadsPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginWebviewPage(),
    ),
    GoRoute(
      path: '/manga/:slugUrl',
      builder: (context, state) {
        final slugUrl = state.pathParameters['slugUrl']!;
        return MangaDetailsPage(slugUrl: slugUrl);
      },
    ),
    GoRoute(
      path: '/read-local',
      builder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return ReaderPage(
          slugUrl: '',
          volume: '1',
          number: '1',
          localCbzPath: filePath,
        );
      },
    ),
    GoRoute(
      path: '/read/:slugUrl/:volume/:number',
      builder: (context, state) {
        final branchIdStr = state.uri.queryParameters['branchId'];
        final branchId = branchIdStr != null ? int.tryParse(branchIdStr) : null;
        return ReaderPage(
          slugUrl: state.pathParameters['slugUrl']!,
          volume: state.pathParameters['volume']!,
          number: state.pathParameters['number']!,
          branchId: branchId,
        );
      },
    ),
  ],
);

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

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

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
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
            icon: const Icon(Icons.search_rounded),
            selectedIcon: const Icon(Icons.search_rounded),
            label: isRu ? 'Поиск' : 'Search',
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
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: isRu ? 'Настройки' : 'Settings',
          ),
        ],
      ),
    );
  }
}

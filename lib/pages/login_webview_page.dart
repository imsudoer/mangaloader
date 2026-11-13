import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/theme/app_tokens.dart';

class LoginWebviewPage extends ConsumerStatefulWidget {
  const LoginWebviewPage({super.key});

  @override
  ConsumerState<LoginWebviewPage> createState() => _LoginWebviewPageState();
}

class _LoginWebviewPageState extends ConsumerState<LoginWebviewPage> {
  static final Uri _siteUri = Uri.parse('https://mangalib.org');

  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _isProcessingLogin = false;
  bool _isProbingSession = false;
  String? _lastProbedHeader;
  final TextEditingController _cookieInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _initWebView();
    }
  }

  @override
  void dispose() {
    _cookieInputController.dispose();
    super.dispose();
  }

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:154.0) Gecko/20100101 Firefox/154.0')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
            _checkCookies();
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            _checkCookies();
          },
          onNavigationRequest: (request) {
            _checkCookies();
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('https://mangalib.org/ru/front/auth'));

    _webViewController = controller;
  }

  Future<void> _checkCookies() async {
    if (_webViewController == null || _isProcessingLogin || _isProbingSession) return;

    _isProbingSession = true;
    try {
      final header = await _readCookieHeader();
      if (header.isEmpty || !_carriesSession(header)) return;
      if (header == ref.read(cookiesProvider) || header == _lastProbedHeader) return;

      _lastProbedHeader = header;
      if (!await _confirmSession(header)) return;
      await _applyCookies(header);
    } finally {
      _isProbingSession = false;
    }
  }

  /// Reads the WebView cookie jar, which is the only place that sees httpOnly
  /// cookies. `document.cookie` cannot: `mangalib_session` and `remember_web_*`
  /// are both httpOnly, so the JS-only capture never produced a usable session.
  Future<String> _readCookieHeader() async {
    final controller = _webViewController;
    if (controller == null) return '';

    try {
      final cookies = await WebViewCookieManager().getCookies(domain: _siteUri);
      final header = cookies
          .where((cookie) => cookie.name.isNotEmpty && cookie.value.isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      if (header.isNotEmpty) return header;
    } catch (_) {
      // Platforms without `getCookies` support fall through to the JS subset,
      // which stays incomplete because the session cookies are httpOnly.
    }

    try {
      final raw = await controller.runJavaScriptReturningResult('document.cookie');
      if (raw is String) {
        return _normalizeCookieInput(raw.replaceAll('"', '').trim());
      }
    } catch (_) {}
    return '';
  }

  bool _carriesSession(String header) =>
      header.contains('mangalib_session=') || header.contains('remember_web_');

  /// `mangalib_session` is handed to anonymous visitors as well, so its presence
  /// proves nothing. The API answers 401 for a session that is not authenticated,
  /// which makes it the only available proof of a real login.
  Future<bool> _confirmSession(String header) async {
    final previous = ref.read(cookiesProvider);
    rust_api.setCookies(cookies: header);

    try {
      await rust_api.getNotificationCount();
      return true;
    } catch (_) {
      rust_api.setCookies(cookies: previous);
      // A remember-web cookie is only issued by a successful sign-in, so keep it
      // as a fallback when the probe itself is unavailable.
      return header.contains('remember_web_');
    }
  }

  /// Accepts a ready `name=value; ...` header or the JSON array produced by
  /// cookie-export extensions and returns the header form the app stores.
  String _normalizeCookieInput(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[')) return trimmed;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return trimmed;
      final pairs = <String>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final value = entry['value'];
        if (name is String && value is String && name.isNotEmpty && value.isNotEmpty) {
          pairs.add('$name=$value');
        }
      }
      return pairs.join('; ');
    } on FormatException {
      return trimmed;
    }
  }

  Future<void> _applyCookies(String cookieString) async {
    if (_isProcessingLogin) return;

    final header = _normalizeCookieInput(cookieString);
    if (header.isEmpty) return;
    setState(() => _isProcessingLogin = true);

    try {
      ref.read(cookiesProvider.notifier).setCookies(header);

      // Extract user info from webview if available
      int? extractedUserId;
      String? extractedUsername;

      if (_webViewController != null) {
        try {
          final jsResult = await _webViewController!.runJavaScriptReturningResult('''
            (function() {
              try {
                var found = null;
                var visited = 0;
                function visit(node, depth) {
                  if (found || !node || typeof node !== 'object' || depth > 6 || visited > 4000) return;
                  visited++;
                  if (typeof node.id === 'number' && typeof node.username === 'string' && node.username) {
                    found = node;
                    return;
                  }
                  if (Array.isArray(node)) {
                    for (var i = 0; i < node.length; i++) visit(node[i], depth + 1);
                    return;
                  }
                  var keys = ['user', 'currentUser', 'auth', 'profile'];
                  for (var k = 0; k < keys.length; k++) visit(node[keys[k]], depth + 1);
                }
                visit(window.__NUXT__, 0);
                if (!found) {
                  try { visit(JSON.parse(localStorage.getItem('auth') || '{}'), 0); } catch (e) {}
                }
                if (!found) return '';
                return JSON.stringify({ id: found.id, username: found.username });
              } catch (e) {
                return '';
              }
            })()
          ''');

          final jsPayload = jsResult is String ? jsResult.trim() : '';
          if (jsPayload.isNotEmpty) {
            // Android may hand back a JSON-quoted string; decode it so escaped
            // quotes do not break the map parse.
            final decodedPayload = jsPayload.startsWith('"') && jsPayload.endsWith('"')
                ? jsonDecode(jsPayload)
                : jsPayload;
            final data = decodedPayload is String && decodedPayload.trim().isNotEmpty
                ? jsonDecode(decodedPayload)
                : null;
            if (data is Map) {
              extractedUserId = data['id'] as int?;
              extractedUsername = data['username'] as String?;
            }
          }
        } catch (_) {}
      }

      if (extractedUserId != null && extractedUserId > 0) {
        try {
          final profile = await rust_api.getUserProfile(userId: extractedUserId);
          ref.read(currentUserProfileProvider.notifier).setProfile(profile);
        } catch (_) {}
      } else if (extractedUsername != null && extractedUsername.isNotEmpty) {
        try {
          final users = await rust_api.searchUsers(query: extractedUsername);
          if (users.isNotEmpty) {
            ref.read(currentUserProfileProvider.notifier).setProfile(users.first);
          }
        } catch (_) {}
      }

      if (mounted) {
        final isRu = Localizations.localeOf(context).languageCode == 'ru';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu ? 'Успешный вход в аккаунт MangaLib!' : 'MangaLib login successful!'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка применения сессии: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingLogin = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'Вход в MangaLib' : 'MangaLib Login'),
        actions: [
          IconButton(
            icon: const Icon(Icons.paste_rounded),
            tooltip: isRu ? 'Вставить Cookie вручную' : 'Paste Cookie manually',
            onPressed: () => _showManualCookieDialog(context, isRu),
          ),
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _webViewController?.reload(),
            ),
        ],
      ),
      body: isMobile && _webViewController != null
        ? Stack(
            children: [
              WebViewWidget(controller: _webViewController!),
              if (_isLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(),
                ),
            ],
          )
        : Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: Card(
                  color: AppTokens.surfaceRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTokens.borderStrong),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTokens.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.account_circle_rounded, size: 28, color: AppTokens.textPrimary),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              isRu ? 'Авторизация MangaLib' : 'MangaLib Authorization',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isRu 
                            ? 'Для входа на десктопе откройте страницу авторизации в браузере, пройдите капчу и вставьте сюда Cookie-строку (mangalib_session=...; XSRF-TOKEN=...) или JSON-экспорт cookie:'
                            : 'Open login in browser, solve captcha, then paste the Cookie header or the JSON cookie export below:',
                          style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTokens.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(42),
                          ),
                          onPressed: () async {
                            final uri = Uri.parse('https://mangalib.org/ru/front/auth');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                          label: Text(isRu ? 'Открыть mangalib.org/ru/front/auth' : 'Open in Browser'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _cookieInputController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'mangalib_session=...; XSRF-TOKEN=...  |  [{"name":...}]',
                            filled: true,
                            fillColor: AppTokens.surfaceBase,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: () {
                            final text = _cookieInputController.text.trim();
                            if (text.isNotEmpty) {
                              _applyCookies(text);
                            }
                          },
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                          label: Text(isRu ? 'Сохранить и войти' : 'Save & Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }

  void _showManualCookieDialog(BuildContext context, bool isRu) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(isRu ? 'Вставить Cookie' : 'Paste Cookie', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'mangalib_session=...; XSRF-TOKEN=...  |  [{"name":...}]',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            onPressed: () {
              Navigator.pop(ctx);
              if (textController.text.trim().isNotEmpty) {
                _applyCookies(textController.text.trim());
              }
            },
            child: Text(isRu ? 'Применить' : 'Apply'),
          ),
        ],
      ),
    );
  }
}

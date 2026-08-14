import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;

final userCookiesProvider = StateProvider<String?>((ref) => null);

class LoginWebviewPage extends ConsumerStatefulWidget {
  const LoginWebviewPage({super.key});

  @override
  ConsumerState<LoginWebviewPage> createState() => _LoginWebviewPageState();
}

class _LoginWebviewPageState extends ConsumerState<LoginWebviewPage> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  String _currentUrl = 'https://mangalib.org/auth/login';
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
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            _checkCookies();
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _checkCookies();
          },
        ),
      )
      ..loadRequest(Uri.parse('https://mangalib.org/auth/login'));

    _webViewController = controller;
  }

  Future<void> _checkCookies() async {
    if (_webViewController == null) return;
    try {
      final cookies = await _webViewController!.runJavaScriptReturningResult('document.cookie') as String;
      final cleanCookies = cookies.replaceAll('"', '').trim();
      if (cleanCookies.contains('mangalib_session') || cleanCookies.contains('remember_web')) {
        _applyCookies(cleanCookies);
      }
    } catch (_) {}
  }

  void _applyCookies(String cookieString) {
    rust_api.setCookies(cookies: cookieString);
    ref.read(userCookiesProvider.notifier).state = cookieString;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Успешный вход в аккаунт MangaLib!')),
      );
      Navigator.pop(context);
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
                  color: const Color(0xFF2C2C2C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFF3E3E3E)),
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
                                color: const Color(0xFF8A897C).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.account_circle_rounded, size: 28, color: Color(0xFFD2D7DF)),
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
                            ? 'Для входа на десктопе откройте страницу авторизации в браузере, пройдите капчу и скопируйте Cookie (или значение mangalib_session) сюда:'
                            : 'Open login in browser, solve captcha, and paste your Cookie string below:',
                          style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8A897C),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(42),
                          ),
                          onPressed: () async {
                            final uri = Uri.parse('https://mangalib.org/auth/login');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                          label: Text(isRu ? 'Открыть mangalib.org/auth/login' : 'Open in Browser'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _cookieInputController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'mangalib_session=...; XSRF-TOKEN=...',
                            filled: true,
                            fillColor: const Color(0xFF1E1E1E),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF8A897C),
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
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(isRu ? 'Вставить Cookie' : 'Paste Cookie', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'mangalib_session=...; XSRF-TOKEN=...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A897C)),
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

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/l10n/strings/recap_strings.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:mangaloader/widgets/recap_card.dart';

class MangaRecapModal extends ConsumerStatefulWidget {
  const MangaRecapModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const MangaRecapModal(),
    );
  }

  @override
  ConsumerState<MangaRecapModal> createState() => _MangaRecapModalState();
}

class _MangaRecapModalState extends ConsumerState<MangaRecapModal> {
  final GlobalKey _cardKey = GlobalKey();
  late Future<MangaRecapData> _recapFuture;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _recapFuture = rust_storage.getMangaRecap();
  }

  void _reload() {
    setState(() => _recapFuture = rust_storage.getMangaRecap());
  }

  RecapStylePreset _styleOf(String value) => RecapStylePreset.values.firstWhere(
        (style) => style.name == value,
        orElse: () => RecapStylePreset.night,
      );

  RecapLayout _layoutOf(String value) => RecapLayout.values.firstWhere(
        (layout) => layout.name == value,
        orElse: () => RecapLayout.poster,
      );

  Future<void> _shareRecapCard(bool isRu) async {
    final s = RecapStrings(isRu);
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/manga_recap_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: s.shareText,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.exportFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = RecapStrings(isRu);
    final userProfile = ref.watch(currentUserProfileProvider);
    final style = _styleOf(ref.watch(recapStyleProvider));
    final layout = _layoutOf(ref.watch(recapLayoutProvider));

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF383838),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppTokens.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        isRu ? 'Твой год в цифрах и обложках' : 'Your year in numbers and covers',
                        style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<MangaRecapData>(
              future: _recapFuture,
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insights_rounded, size: 42, color: AppTokens.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            s.loadFailed,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTokens.textSecondary),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonal(onPressed: _reload, child: Text(isRu ? 'Повторить' : 'Retry')),
                        ],
                      ),
                    ),
                  );
                }

                final recap = snapshot.data!;
                final topManga = recap.topManga
                    .where((m) =>
                        !ContentFilter.isBlockedText(m.name) &&
                        !ContentFilter.isBlockedText(m.rusName))
                    .toList();
                final cardWidth = (MediaQuery.sizeOf(context).width - 48).clamp(300.0, 400.0);

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStylePicker(s, style),
                      const SizedBox(height: 10),
                      _buildLayoutPicker(s, layout),
                      const SizedBox(height: 14),
                      Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.02),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: RepaintBoundary(
                            key: _cardKey,
                            child: RecapCard(
                              key: ValueKey('${style.name}-${layout.name}'),
                              data: recap,
                              topManga: topManga,
                              style: style,
                              layout: layout,
                              width: cardWidth,
                              isRu: isRu,
                              username: userProfile?.username,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isExporting ? null : () => _shareRecapCard(isRu),
                        icon: _isExporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.share_rounded, size: 20),
                        label: Text(
                          s.shareCard,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppTokens.textSecondary,
            fontSize: 9.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _buildStylePicker(RecapStrings s, RecapStylePreset selected) {
    final options = [
      (RecapStylePreset.night, s.styleNight),
      (RecapStylePreset.paper, s.stylePaper),
      (RecapStylePreset.neon, s.styleNeon),
      (RecapStylePreset.kimono, s.styleKimono),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(s.styleLabel),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _styleChip(options[i].$1, options[i].$2, options[i].$1 == selected),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _styleChip(RecapStylePreset style, String label, bool selected) {
    final palette = RecapPalette.of(style);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => ref.read(recapStyleProvider.notifier).set(style.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTokens.accent.withValues(alpha: 0.18) : AppTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTokens.accent : AppTokens.borderStrong,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: palette.background),
                shape: BoxShape.circle,
                border: Border.all(color: palette.accent, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : AppTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutPicker(RecapStrings s, RecapLayout selected) {
    final options = [
      (RecapLayout.poster, s.layoutPoster, Icons.grid_view_rounded),
      (RecapLayout.dossier, s.layoutDossier, Icons.article_outlined),
      (RecapLayout.timeline, s.layoutTimeline, Icons.view_timeline_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(s.layoutLabel),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _layoutChip(
                  options[i].$1,
                  options[i].$2,
                  options[i].$3,
                  options[i].$1 == selected,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _layoutChip(RecapLayout layout, String label, IconData icon, bool selected) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => ref.read(recapLayoutProvider.notifier).set(layout.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTokens.accent.withValues(alpha: 0.18) : AppTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTokens.accent : AppTokens.borderStrong,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? AppTokens.accent : AppTokens.textSecondary),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : AppTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
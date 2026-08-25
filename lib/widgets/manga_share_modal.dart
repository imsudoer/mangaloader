import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/src/rust/api/models.dart';

class MangaShareModal extends StatefulWidget {
  final MangaDetails manga;
  final Color accentColor;

  const MangaShareModal({
    super.key,
    required this.manga,
    required this.accentColor,
  });

  static Future<void> show(BuildContext context, MangaDetails manga, Color accentColor) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MangaShareModal(manga: manga, accentColor: accentColor),
    );
  }

  @override
  State<MangaShareModal> createState() => _MangaShareModalState();
}

class _MangaShareModalState extends State<MangaShareModal> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isExporting = false;

  Future<void> _shareCard(bool isRu) async {
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
      final file = File('${tempDir.path}/manga_card_${widget.manga.id}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      if (!mounted) return;
      final isRu = Localizations.localeOf(context).languageCode == 'ru';
      final title = widget.manga.rusName.isNotEmpty ? widget.manga.rusName : widget.manga.name;
      final shareText = '$title\nhttps://mangalib.org/ru/manga/${widget.manga.slugUrl}\n${isRu ? "Читайте в MangaLoader!" : "Read on MangaLoader!"}';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
        ),
      );
    } catch (e) {
      if (mounted) {
        final isRu = Localizations.localeOf(context).languageCode == 'ru';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRu ? 'Ошибка создания карточки: $e' : 'Failed to create card: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final title = widget.manga.rusName.isNotEmpty ? widget.manga.rusName : widget.manga.name;
    final ratingNum = double.tryParse(widget.manga.ratingAverage) ?? 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isRu ? 'Поделиться тайтлом' : 'Share Title Card',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // RepaintBoundary for high-res card export
          SingleChildScrollView(
            child: RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accentColor.withValues(alpha: 0.35),
                      const Color(0xFF1E1E1E),
                      const Color(0xFF121212),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: widget.accentColor.withValues(alpha: 0.5), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top App Branding
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: widget.accentColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 14),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'MangaLoader',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                        ),
                        const Spacer(),
                        if (widget.manga.mangaType.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: widget.accentColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              widget.manga.mangaType,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: widget.accentColor),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Cover + Title side-by-side or stacked
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: widget.manga.coverUrl,
                            httpHeaders: const {'Referer': 'https://mangalib.org/'},
                            width: 100,
                            height: 145,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(width: 100, height: 145, color: const Color(0xFF2C2C2C)),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Title Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  height: 1.25,
                                ),
                              ),
                              if (widget.manga.engName.isNotEmpty && widget.manga.engName != title) ...[
                                const SizedBox(height: 3),
                                Text(
                                  widget.manga.engName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0)),
                                ),
                              ],
                              const SizedBox(height: 8),

                              // Rating
                              if (ratingNum > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 16, color: Colors.amberAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.manga.ratingAverage,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    if (widget.manga.ratingVotes.isNotEmpty)
                                      Text(
                                        ' (${widget.manga.ratingVotes})',
                                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 6),

                              // Chapters count
                              if (widget.manga.chaptersCount > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.library_books_rounded, size: 14, color: Color(0xFF81C784)),
                                    const SizedBox(width: 4),
                                    Text(
                                      isRu ? '${widget.manga.chaptersCount} глав' : '${widget.manga.chaptersCount} chapters',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF81C784), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Genres
                    if (widget.manga.genres.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: widget.manga.genres.take(5).map((g) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2C),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              g.name,
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFFD2D7DF)),
                            ),
                          )).toList(),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Footer Link
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, size: 14, color: Colors.white54),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'mangalib.org/ru/manga/${widget.manga.slugUrl}',
                              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD2D7DF),
                    side: const BorderSide(color: Color(0xFF444444)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: 'https://mangalib.org/ru/manga/${widget.manga.slugUrl}',
                        subject: title,
                      ),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(isRu ? 'Только ссылка' : 'Link only'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isExporting ? null : () => _shareCard(isRu),
                  icon: _isExporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.image_rounded, size: 18),
                  label: Text(isRu ? 'Поделиться карточкой' : 'Share Card'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

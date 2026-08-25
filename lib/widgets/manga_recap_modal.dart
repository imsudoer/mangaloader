import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

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
  bool _isExporting = false;

  Future<void> _shareRecapCard(bool isRu) async {
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
          text: isRu ? 'Мои итоги чтения в MangaLoader!' : 'My Reading Recap in MangaLoader!',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRu ? 'Ошибка экспорта карточки: $e' : 'Failed to export card: $e')),
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
    final userProfile = ref.watch(currentUserProfileProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8A897C), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      isRu ? 'Manga Recap / Итоги чтения' : 'Manga Reading Recap',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
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
              future: rust_storage.getMangaRecap(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return Center(
                    child: Text(
                      isRu ? 'Ошибка загрузки статистики' : 'Failed to load recap data',
                      style: const TextStyle(color: Color(0xFFBDBBB0)),
                    ),
                  );
                }

                final recap = snapshot.data!;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // The Shareable Recap Card (RepaintBoundary)
                      RepaintBoundary(
                        key: _cardKey,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF262626), Color(0xFF1A1A1A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF3E3E3E), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Card Header with Logo / User
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8A897C).withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.menu_book_rounded, color: Color(0xFFD2D7DF), size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'MANGA LOADER',
                                            style: TextStyle(
                                              color: Color(0xFFD2D7DF),
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            userProfile != null ? userProfile.username : (isRu ? 'Итоги чтения' : 'Recap Summary'),
                                            style: const TextStyle(color: Color(0xFF8A897C), fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF383838),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${DateTime.now().year}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Big Stats Row
                              Row(
                                children: [
                                  _buildStatBlock(
                                    title: isRu ? 'Глав прочитано' : 'Chapters Read',
                                    value: '${recap.totalChaptersRead}',
                                    icon: Icons.check_circle_outline_rounded,
                                    color: const Color(0xFF8A897C),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildStatBlock(
                                    title: isRu ? 'Страниц' : 'Pages Read',
                                    value: '${recap.totalPagesRead}',
                                    icon: Icons.pages_rounded,
                                    color: const Color(0xFF6B8E23),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildStatBlock(
                                    title: isRu ? 'Часов чтения' : 'Hours Read',
                                    value: '${recap.estimatedReadingHours} ${isRu ? "ч" : "h"}',
                                    icon: Icons.timer_outlined,
                                    color: const Color(0xFF4682B4),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildStatBlock(
                                    title: isRu ? 'Лучший стрик' : 'Max Streak',
                                    value: '${recap.maxStreak} ${isRu ? "дн." : "days"}',
                                    icon: Icons.local_fire_department_rounded,
                                    color: Colors.orange,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Top Genres
                              if (recap.topGenres.isNotEmpty) ...[
                                Text(
                                  isRu ? 'Любимые жанры' : 'Favorite Genres',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                ...recap.topGenres.take(3).map((g) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(g.name, style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 12)),
                                              Text('${g.percentage}%', style: const TextStyle(color: Color(0xFF8A897C), fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: g.percentage / 100.0,
                                              backgroundColor: const Color(0xFF333333),
                                              valueColor: const AlwaysStoppedAnimation(Color(0xFF8A897C)),
                                              minHeight: 6,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                const SizedBox(height: 14),
                              ],

                              // Top Manga Read
                              if (recap.topManga.isNotEmpty) ...[
                                Text(
                                  isRu ? 'Топ прочитанных тайтлов' : 'Top Read Manga',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                ...recap.topManga.take(3).map((m) {
                                  final title = m.rusName.isNotEmpty ? m.rusName : m.name;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: SizedBox(
                                            width: 32,
                                            height: 44,
                                            child: m.coverUrl.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: m.coverUrl,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (_, __, ___) => const Icon(Icons.image, size: 16),
                                                  )
                                                : const Icon(Icons.image, size: 16),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF333333),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${m.chaptersRead} ${isRu ? "гл." : "ch."}',
                                            style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 11),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Share Action Button
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8A897C),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isExporting ? null : () => _shareRecapCard(isRu),
                        icon: _isExporting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.share_rounded, size: 20),
                        label: Text(
                          isRu ? 'Поделиться карточкой итогов' : 'Share Recap Card',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 20),
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

  Widget _buildStatBlock({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF353535)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 11)),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

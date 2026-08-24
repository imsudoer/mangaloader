import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/providers/continue_reading_provider.dart';
import 'package:mangaloader/src/rust/api/models.dart';

class ContinueReadingSection extends ConsumerWidget {
  final bool isRu;
  const ContinueReadingSection({super.key, required this.isRu});

  double _calculateProgress(ContinueReadingItem item) {
    if (item.totalChapters > 0) {
      if (item.readChapters > 0) {
        return (item.readChapters / item.totalChapters).clamp(0.0, 1.0);
      }
      final chNum = double.tryParse(item.lastReadChapter) ?? 0.0;
      if (chNum > 0) {
        return (chNum / item.totalChapters).clamp(0.0, 1.0);
      }
    }
    return 0.05;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueAsync = ref.watch(continueReadingProvider);

    return continueAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A897C).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF8A897C), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRu ? 'Продолжить чтение' : 'Continue Reading',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        Text(
                          isRu ? 'Ваш текущий прогресс' : 'Your recent reading progress',
                          style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/library'),
                    child: Text(isRu ? 'Библиотека' : 'Library', style: const TextStyle(fontSize: 12, color: Color(0xFF8A897C))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, idx) {
                  final item = items[idx];
                  final title = item.rusName.isNotEmpty ? item.rusName : item.name;
                  final progress = _calculateProgress(item);

                  return SizedBox(
                    width: 152,
                    child: Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF353535), width: 1),
                      ),
                      child: InkWell(
                        onTap: () async {
                          await context.push('/manga/${item.slugUrl}');
                          ref.invalidate(continueReadingProvider);
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Cover
                            CachedNetworkImage(
                              imageUrl: item.coverUrl,
                              httpHeaders: const {'Referer': 'https://mangalib.org/'},
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: const Color(0xFF242424)),
                              errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white38),
                            ),
                            // Gradient
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.92),
                                    ],
                                    stops: const [0.35, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            // Unread Chapters Badge (Top-Left)
                            if (item.unreadCount > 0)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E1E).withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.5)),
                                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.menu_book_rounded, size: 12, color: Color(0xFFD2D7DF)),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${item.unreadCount} ${isRu ? "не прочит." : "unread"}',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFD2D7DF)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Quick Play Button (Center-Bottom)
                            Positioned(
                              bottom: 44,
                              right: 8,
                              child: IconButton.filled(
                                onPressed: () async {
                                  await context.push('/read/${item.slugUrl}/${item.lastReadVolume}/${item.lastReadChapter}');
                                  ref.invalidate(continueReadingProvider);
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF8A897C),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(34, 34),
                                  padding: EdgeInsets.zero,
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              ),
                            ),
                            // Title & Progress Bar
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      shadows: [
                                        Shadow(color: Colors.black, blurRadius: 3),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: progress > 0 ? progress : 0.05,
                                      minHeight: 3.5,
                                      backgroundColor: const Color(0xFF333333),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A897C)),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Т.${item.lastReadVolume} Гл.${item.lastReadChapter}',
                                          style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 10, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (progress > 0)
                                        Text(
                                          '${(progress * 100).toInt()}%',
                                          style: const TextStyle(color: Color(0xFF8A897C), fontSize: 9.5, fontWeight: FontWeight.bold),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

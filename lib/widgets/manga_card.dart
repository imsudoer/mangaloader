import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/providers/library_provider.dart';

class MangaCard extends ConsumerWidget {
  final MangaSearchResult manga;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const MangaCard({super.key, required this.manga, required this.onTap, this.onLongPress});

  Widget? _buildLibraryStatusBadge(BuildContext context, WidgetRef ref) {
    final libraryList = ref.watch(libraryProvider).value ?? [];
    final libItem = libraryList.where((e) => e.mangaId == manga.id).firstOrNull;

    if (libItem == null) return null;

    IconData icon;
    Color color;
    String tooltip;

    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    switch (libItem.listType) {
      case ListType.reading:
        icon = Icons.auto_stories_rounded;
        color = const Color(0xFF64B5F6);
        tooltip = isRu ? 'Читаю' : 'Reading';
        break;
      case ListType.planToRead:
        icon = Icons.bookmark_rounded;
        color = const Color(0xFFFFB74D);
        tooltip = isRu ? 'В планах' : 'Plan to Read';
        break;
      case ListType.completed:
        icon = Icons.check_circle_rounded;
        color = const Color(0xFF81C784);
        tooltip = isRu ? 'Прочитано' : 'Completed';
        break;
      case ListType.favorites:
        icon = Icons.favorite_rounded;
        color = const Color(0xFFF06292);
        tooltip = isRu ? 'Любимое' : 'Favorites';
        break;
      case ListType.dropped:
        icon = Icons.delete_outline_rounded;
        color = Colors.redAccent;
        tooltip = isRu ? 'Брошено' : 'Dropped';
        break;
      case ListType.onHold:
        icon = Icons.pause_circle_outline_rounded;
        color = Colors.grey;
        tooltip = isRu ? 'Отложено' : 'On Hold';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = manga.rusName.isNotEmpty ? manga.rusName : manga.name;
    final colorScheme = Theme.of(context).colorScheme;
    final libBadge = _buildLibraryStatusBadge(context, ref);
    final ratingNum = double.tryParse(manga.ratingAverage) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        color: colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333333), width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'cover_${manga.slugUrl}',
                child: CachedNetworkImage(
                  imageUrl: manga.coverUrl,
                  httpHeaders: const {'Referer': 'https://mangalib.org/'},
                  fit: BoxFit.cover,
                  memCacheWidth: 320,
                  memCacheHeight: 480,
                  placeholder: (context, url) => Container(color: const Color(0xFF262626)),
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFF262626),
                    child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white38)),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.92),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ratingNum > 0) ...[
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 13, color: Colors.amberAccent),
                          const SizedBox(width: 3),
                          Text(
                            manga.ratingAverage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Top Right: Library status icon badge
              if (libBadge != null)
                Positioned(
                  top: 7,
                  right: 7,
                  child: libBadge,
                ),
              // Top Left: Manga Type
              if (manga.mangaType.isNotEmpty)
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Text(
                      manga.mangaType,
                      style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

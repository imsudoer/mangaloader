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

    switch (libItem.listType) {
      case ListType.reading:
        icon = Icons.auto_stories_rounded;
        color = const Color(0xFF64B5F6);
        tooltip = 'Читаю';
        break;
      case ListType.planToRead:
        icon = Icons.bookmark_rounded;
        color = const Color(0xFFFFB74D);
        tooltip = 'В планах';
        break;
      case ListType.completed:
        icon = Icons.check_circle_rounded;
        color = const Color(0xFF81C784);
        tooltip = 'Прочитано';
        break;
      case ListType.favorites:
        icon = Icons.favorite_rounded;
        color = const Color(0xFFF06292);
        tooltip = 'Любимое';
        break;
      case ListType.dropped:
        icon = Icons.delete_outline_rounded;
        color = Colors.redAccent;
        tooltip = 'Брошено';
        break;
      case ListType.onHold:
        icon = Icons.pause_circle_outline_rounded;
        color = Colors.grey;
        tooltip = 'Отложено';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = manga.rusName.isNotEmpty ? manga.rusName : manga.name;
    final colorScheme = Theme.of(context).colorScheme;
    final libBadge = _buildLibraryStatusBadge(context, ref);

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3E3E3E), width: 0.8),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: manga.coverUrl,
              httpHeaders: const {'Referer': 'https://mangalib.org/'},
              fit: BoxFit.cover,
              memCacheWidth: 320,
              memCacheHeight: 480,
              placeholder: (context, url) => Container(color: colorScheme.surfaceContainerHighest),
              errorWidget: (context, url, error) => const Icon(Icons.error_rounded),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            // Top Right: Library status icon badge
            if (libBadge != null)
              Positioned(
                top: 8,
                right: 8,
                child: libBadge,
              ),
            // Top Left: Manga Type
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF353535).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.6), width: 0.8),
                ),
                child: Text(
                  manga.mangaType,
                  style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (onLongPress != null)
              Positioned(
                bottom: 38,
                right: 8,
                child: IconButton.filled(
                  onPressed: onLongPress,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF8A897C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(6),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

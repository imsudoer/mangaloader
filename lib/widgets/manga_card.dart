import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/providers/library_provider.dart';
import 'package:mangaloader/theme/app_tokens.dart';

/// Tag shared by a cover thumbnail and the large cover on the details header.
String coverHeroTag(String slugUrl) => 'cover-$slugUrl';

/// Declares a cover-hero namespace. The shell keeps several screens mounted at
/// once, and a tag may only be claimed by one live Hero per namespace, so each
/// tab gets its own scope while a flight to the details page still matches on
/// the plain [coverHeroTag] string.
class CoverHeroScope extends InheritedWidget {
  const CoverHeroScope({super.key, required super.child});

  @override
  bool updateShouldNotify(CoverHeroScope oldWidget) => false;
}

/// Claims a hero tag for its subtree. The first card of a given title inside a
/// scope owns the tag; duplicates stay static instead of throwing
/// "multiple heroes share the same tag" when a flight starts.
class _CoverHero extends StatefulWidget {
  const _CoverHero({required this.tag, required this.child});

  final String tag;
  final Widget child;

  @override
  State<_CoverHero> createState() => _CoverHeroState();
}

class _CoverHeroState extends State<_CoverHero> {
  static final Object _globalScope = Object();

  Object? _scope;
  String? _claimedTag;
  bool _ownsTag = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClaim();
  }

  @override
  void didUpdateWidget(covariant _CoverHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag) _syncClaim();
  }

  @override
  void dispose() {
    _releaseClaim();
    super.dispose();
  }

  void _syncClaim() {
    final scope = context.getElementForInheritedWidgetOfExactType<CoverHeroScope>() ??
        ModalRoute.of(context) ??
        _globalScope;
    if (_claimedTag == widget.tag && identical(_scope, scope)) return;
    _releaseClaim();
    _scope = scope;
    _claimedTag = widget.tag;
    _ownsTag = _CoverHeroRegistry.claim(scope, widget.tag, this);
  }

  void _releaseClaim() {
    final scope = _scope;
    final tag = _claimedTag;
    if (scope == null || tag == null) return;
    _CoverHeroRegistry.release(scope, tag, this);
    _scope = null;
    _claimedTag = null;
    _ownsTag = false;
  }

  void _promote() {
    if (!mounted || _ownsTag) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ownsTag = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return HeroMode(
      enabled: _ownsTag,
      child: Hero(tag: widget.tag, child: widget.child),
    );
  }
}

class _CoverHeroRegistry {
  static final Map<Object, Map<String, List<_CoverHeroState>>> _owners = {};

  static bool claim(Object scope, String tag, _CoverHeroState hero) {
    final byTag = _owners.putIfAbsent(
      scope,
      () => <String, List<_CoverHeroState>>{},
    );
    final queue = byTag.putIfAbsent(tag, () => <_CoverHeroState>[]);
    queue.add(hero);
    return identical(queue.first, hero);
  }

  static void release(Object scope, String tag, _CoverHeroState hero) {
    final byTag = _owners[scope];
    final queue = byTag?[tag];
    if (byTag == null || queue == null) return;
    final wasOwner = queue.isNotEmpty && identical(queue.first, hero);
    queue.remove(hero);
    if (queue.isEmpty) {
      byTag.remove(tag);
      if (byTag.isEmpty) _owners.remove(scope);
      return;
    }
    if (wasOwner) queue.first._promote();
  }
}

class MangaCard extends ConsumerWidget {
  final MangaSearchResult manga;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Set to false in contexts rendered outside a ProviderScope, or where the
  /// library indicator is redundant (the library screen itself).
  final bool showLibraryBadge;

  const MangaCard({
    super.key,
    required this.manga,
    required this.onTap,
    this.onLongPress,
    this.showLibraryBadge = true,
  });

  Widget? _buildLibraryStatusBadge(BuildContext context, WidgetRef ref) {
    // Only the membership of this single title is watched, so the card is not
    // rebuilt when another title changes list.
    final listType = ref.watch(mangaListTypeProvider(manga.id.toInt()));
    if (listType == null) return null;

    IconData icon;
    Color color;
    String tooltip;

    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    switch (listType) {
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
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1),
        ),
        child: Icon(icon, size: 12, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = manga.rusName.isNotEmpty ? manga.rusName : manga.name;
    final colorScheme = Theme.of(context).colorScheme;
    final libBadge = showLibraryBadge ? _buildLibraryStatusBadge(context, ref) : null;
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
              _CoverHero(
                tag: coverHeroTag(manga.slugUrl),
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
                      border: Border.all(color: AppTokens.accent.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Text(
                      manga.mangaType,
                      style: const TextStyle(color: AppTokens.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w600),
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

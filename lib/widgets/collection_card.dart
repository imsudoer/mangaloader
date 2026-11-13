import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/widgets/collection_details_modal.dart';
import 'package:mangaloader/theme/app_tokens.dart';

class CollectionCard extends StatelessWidget {
  final MangaCollectionItem collection;

  const CollectionCard({
    super.key,
    required this.collection,
  });

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    // A user collection may be titled after prohibited media, so it is hidden in
    // builds that are subject to the local content regulations.
    if (ContentFilter.isBlockedText(collection.name) ||
        ContentFilter.isBlockedText(collection.description)) {
      return const SizedBox.shrink();
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppTokens.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTokens.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          CollectionDetailsModal.show(
            context,
            collectionId: collection.id,
            fallbackTitle: collection.name,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Author & Views
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFF383838),
                    backgroundImage: collection.userAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(collection.userAvatar)
                      : null,
                    child: collection.userAvatar.isEmpty
                      ? Text(
                          collection.username.isNotEmpty ? collection.username[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      collection.username.isNotEmpty ? collection.username : (isRu ? 'Пользователь' : 'User'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppTokens.textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Icon(Icons.menu_book_rounded, size: 12, color: Color(0xFF888888)),
                  const SizedBox(width: 4),
                  Text(
                    '${collection.itemsCount}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                collection.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),

              if (collection.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  collection.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFAAAAAA),
                    height: 1.3,
                  ),
                ),
              ],

              const Spacer(),

              // Bottom Stats Row
              Row(
                children: [
                  const Icon(Icons.visibility_rounded, size: 12, color: Color(0xFF888888)),
                  const SizedBox(width: 4),
                  Text(
                    '${collection.views}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.thumb_up_alt_rounded, size: 12, color: Color(0xFF888888)),
                  const SizedBox(width: 4),
                  Text(
                    '${collection.votesUp}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTokens.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isRu ? 'Открыть' : 'View',
                      style: const TextStyle(fontSize: 10, color: AppTokens.textPrimary, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

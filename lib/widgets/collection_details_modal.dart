import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/widgets/manga_card.dart';

class CollectionDetailsModal extends StatefulWidget {
  final int collectionId;
  final String fallbackTitle;

  const CollectionDetailsModal({
    super.key,
    required this.collectionId,
    required this.fallbackTitle,
  });

  static void show(BuildContext context, {required int collectionId, required String fallbackTitle}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => CollectionDetailsModal(
        collectionId: collectionId,
        fallbackTitle: fallbackTitle,
      ),
    );
  }

  @override
  State<CollectionDetailsModal> createState() => _CollectionDetailsModalState();
}

class _CollectionDetailsModalState extends State<CollectionDetailsModal> {
  MangaCollectionDetails? _details;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final data = await rust_api.getCollectionDetails(collectionId: widget.collectionId);
      if (mounted) {
        setState(() {
          _details = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF444444),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: Color(0xFFD2D7DF))),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _loadDetails();
                      },
                      child: Text(isRu ? 'Повторить' : 'Retry'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _details?.name ?? widget.fallbackTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_details?.username.isNotEmpty ?? false) ...[
                            CircleAvatar(
                              radius: 10,
                              backgroundImage: _details!.userAvatar.isNotEmpty
                                ? CachedNetworkImageProvider(_details!.userAvatar)
                                : null,
                              child: _details!.userAvatar.isEmpty
                                ? Text(_details!.username[0].toUpperCase(), style: const TextStyle(fontSize: 8))
                                : null,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _details!.username,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                            ),
                            const SizedBox(width: 12),
                          ],
                          const Icon(Icons.menu_book_rounded, size: 14, color: Color(0xFF888888)),
                          const SizedBox(width: 4),
                          Text(
                            '${_details?.items.length ?? 0} ${isRu ? "тайтлов" : "titles"}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.visibility_rounded, size: 14, color: Color(0xFF888888)),
                          const SizedBox(width: 4),
                          Text(
                            '${_details?.views ?? 0}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_details?.description.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _details!.description,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC), height: 1.35),
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFF333333)),
            const SizedBox(height: 12),

            // Titles Grid
            Expanded(
              child: _details?.items.isEmpty ?? true
                ? Center(
                    child: Text(
                      isRu ? 'В коллекции нет тайтлов' : 'No titles in collection',
                      style: const TextStyle(color: Color(0xFF888888)),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _details!.items.length,
                    itemBuilder: (ctx, idx) {
                      final item = _details!.items[idx];
                      return MangaCard(
                        manga: item,
                        onTap: () {
                          context.push('/manga/${item.slugUrl}');
                        },
                      );
                    },
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

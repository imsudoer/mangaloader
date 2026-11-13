import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/l10n/strings/user_search_strings.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/theme/app_tokens.dart';

class UserSearchModal extends StatefulWidget {
  const UserSearchModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const UserSearchModal(),
    );
  }

  @override
  State<UserSearchModal> createState() => _UserSearchModalState();
}

class _UserSearchModalState extends State<UserSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  List<UserProfile> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await rust_api.searchUsers(query: q);
      if (mounted) {
        setState(() {
          _users = results;
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

  void _showUserProfileDialog(UserProfile user, bool isRu) async {
    final s = UserSearchStrings(isRu);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTokens.border,
              backgroundImage: user.avatarUrl.isNotEmpty ? CachedNetworkImageProvider(user.avatarUrl) : null,
              child: user.avatarUrl.isEmpty ? const Icon(Icons.person, color: AppTokens.accent) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user.username,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${user.id}', style: const TextStyle(color: AppTokens.textPrimary, fontSize: 13)),
            if (user.createdAt != null && user.createdAt!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                s.joined(user.createdAt!.split("T").first),
                style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 16),
                const SizedBox(width: 4),
                Text(
                  s.loginStreak('${user.loginStreak}'),
                  style: const TextStyle(color: AppTokens.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.close),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            onPressed: () {
              Navigator.pop(ctx);
              _viewUserBookmarks(user, isRu);
            },
            icon: const Icon(Icons.bookmarks_rounded, size: 16),
            label: Text(s.bookmarks),
          ),
        ],
      ),
    );
  }

  void _viewUserBookmarks(UserProfile user, bool isRu) async {
    final s = UserSearchStrings(isRu);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx2, scrollCtrl) {
            return FutureBuilder<List<MangaSearchResult>>(
              future: rust_api.getUserBookmarks(userId: user.id, status: 1),
              builder: (ctx3, snapshot) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.bookmarksOf(user.username),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Expanded(child: Center(child: CircularProgressIndicator()))
                      else if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              s.noBookmarks,
                              style: const TextStyle(color: AppTokens.textSecondary),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            controller: scrollCtrl,
                            itemCount: snapshot.data!.length,
                            itemBuilder: (ctx4, idx) {
                              final manga = snapshot.data![idx];
                              final title = manga.rusName.isNotEmpty ? manga.rusName : manga.name;
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 40,
                                    height: 56,
                                    child: CachedNetworkImage(
                                      imageUrl: manga.coverUrl,
                                      memCacheWidth: 200,
                                      memCacheHeight: 280,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(manga.mangaType, style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  Navigator.pop(context);
                                  context.push('/manga/${manga.slugUrl}');
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = UserSearchStrings(isRu);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppTokens.surfaceBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF383838),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: AppTokens.accent),
              const SizedBox(width: 8),
              Text(
                s.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: s.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => _performSearch(_searchController.text),
              ),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: _performSearch,
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Text('Ошибка поиска: $_errorMessage', style: const TextStyle(color: Colors.redAccent)),
              ),
            )
          else if (_users.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  s.emptyPrompt,
                  style: const TextStyle(color: AppTokens.textSecondary),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _users.length,
                itemBuilder: (ctx, i) {
                  final u = _users[i];
                  return Card(
                    color: const Color(0xFF282828),
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFF383838)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTokens.border,
                        backgroundImage: u.avatarUrl.isNotEmpty ? CachedNetworkImageProvider(u.avatarUrl) : null,
                        child: u.avatarUrl.isEmpty ? const Icon(Icons.person, color: AppTokens.accent) : null,
                      ),
                      title: Text(u.username, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text('ID: ${u.id}', style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppTokens.textSecondary),
                      onTap: () => _showUserProfileDialog(u, isRu),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

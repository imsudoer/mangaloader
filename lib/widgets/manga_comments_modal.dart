import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';

class MangaCommentsModal extends ConsumerStatefulWidget {
  final String relationType; // "media" or "chapter"
  final int relationId;
  final String title;

  const MangaCommentsModal({
    super.key,
    required this.relationType,
    required this.relationId,
    required this.title,
  });

  static void show(BuildContext context, {
    required String relationType,
    required int relationId,
    required String title,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => MangaCommentsModal(
        relationType: relationType,
        relationId: relationId,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<MangaCommentsModal> createState() => _MangaCommentsModalState();
}

class _MangaCommentsModalState extends ConsumerState<MangaCommentsModal> {
  final List<CommentItem> _rootComments = [];
  final List<CommentItem> _replies = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 1;
  String _sort = 'votes'; // 'votes' or 'new'
  String? _errorMessage;

  final TextEditingController _commentController = TextEditingController();
  CommentItem? _replyingTo;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _rootComments.clear();
      _replies.clear();
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await rust_api.getComments(
        relationType: widget.relationType,
        relationId: widget.relationId,
        page: _currentPage,
        sort: _sort,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _rootComments.clear();
            _replies.clear();
          }
          _rootComments.addAll(data.root);
          _replies.addAll(data.replies);
          _hasNextPage = data.hasNextPage;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _vote(CommentItem comment, int vote) async {
    final profile = ref.read(currentUserProfileProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRu ? 'Войдите в аккаунт, чтобы голосовать' : 'Sign in to vote'),
          action: SnackBarAction(
            label: isRu ? 'Войти' : 'Sign In',
            onPressed: () => context.push('/login'),
          ),
        ),
      );
      return;
    }

    final newVote = comment.userVote == vote ? 0 : vote;
    
    // Optimistic UI update
    setState(() {
      final idx = _rootComments.indexWhere((c) => c.id == comment.id);
      if (idx != -1) {
        final current = _rootComments[idx];
        int up = current.votesUp;
        int down = current.votesDown;

        if (current.userVote == 1) up--;
        if (current.userVote == -1) down--;

        if (newVote == 1) up++;
        if (newVote == -1) down++;

        _rootComments[idx] = CommentItem(
          id: current.id,
          userId: current.userId,
          rootId: current.rootId,
          parentComment: current.parentComment,
          commentLevel: current.commentLevel,
          postPage: current.postPage,
          text: current.text,
          createdAt: current.createdAt,
          username: current.username,
          userAvatar: current.userAvatar,
          votesUp: up,
          votesDown: down,
          userVote: newVote == 0 ? null : newVote,
        );
      }
    });

    try {
      final res = await rust_api.voteComment(commentId: comment.id, vote: newVote);
      if (res.success && mounted) {
        setState(() {
          final idx = _rootComments.indexWhere((c) => c.id == comment.id);
          if (idx != -1) {
            final current = _rootComments[idx];
            _rootComments[idx] = CommentItem(
              id: current.id,
              userId: current.userId,
              rootId: current.rootId,
              parentComment: current.parentComment,
              commentLevel: current.commentLevel,
              postPage: current.postPage,
              text: current.text,
              createdAt: current.createdAt,
              username: current.username,
              userAvatar: current.userAvatar,
              votesUp: res.votesUp,
              votesDown: res.votesDown,
              userVote: res.userVote,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _postComment(bool isRu) async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isPosting) return;

    final profile = ref.read(currentUserProfileProvider);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRu ? 'Войдите в аккаунт, чтобы оставить комментарий' : 'Sign in to post comments'),
          action: SnackBarAction(
            label: isRu ? 'Войти' : 'Sign In',
            onPressed: () => context.push('/login'),
          ),
        ),
      );
      return;
    }

    setState(() => _isPosting = true);
    try {
      final newComment = await rust_api.addComment(
        relationType: widget.relationType,
        relationId: widget.relationId,
        comment: text,
        parentId: _replyingTo?.id,
      );

      _commentController.clear();
      setState(() {
        if (_replyingTo == null) {
          _rootComments.insert(0, newComment);
        } else {
          _replies.add(newComment);
        }
        _replyingTo = null;
        _isPosting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu ? 'Комментарий опубликован' : 'Comment posted'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
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

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRu ? 'Комментарии' : 'Comments',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0)),
                      ),
                    ],
                  ),
                ),
                // Sort Segmented Button
                SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    selectedBackgroundColor: const Color(0xFF8A897C),
                    selectedForegroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  segments: [
                    ButtonSegment(value: 'votes', label: Text(isRu ? 'Топ' : 'Top')),
                    ButtonSegment(value: 'new', label: Text(isRu ? 'Новые' : 'New')),
                  ],
                  selected: {_sort},
                  onSelectionChanged: (val) {
                    setState(() => _sort = val.first);
                    _loadComments(refresh: true);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF333333)),

          // Comments List
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, style: const TextStyle(color: Color(0xFFD2D7DF))),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => _loadComments(refresh: true),
                          child: Text(isRu ? 'Повторить' : 'Retry'),
                        ),
                      ],
                    ),
                  )
                : _rootComments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Color(0xFF555555)),
                          const SizedBox(height: 12),
                          Text(
                            isRu ? 'Комментариев пока нет' : 'No comments yet',
                            style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isRu ? 'Будьте первым, кто оставит комментарий!' : 'Be the first to comment!',
                            style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (scrollInfo) {
                        if (!_isLoadingMore && _hasNextPage && scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                          setState(() {
                            _isLoadingMore = true;
                            _currentPage++;
                          });
                          _loadComments();
                        }
                        return false;
                      },
                      child: RefreshIndicator(
                        onRefresh: () => _loadComments(refresh: true),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _rootComments.length + (_hasNextPage ? 1 : 0),
                          itemBuilder: (ctx, idx) {
                            if (idx >= _rootComments.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            final comment = _rootComments[idx];
                            final commentReplies = _replies.where((r) => r.rootId == comment.id || r.parentComment == comment.id).toList();

                            return _buildCommentTile(comment, commentReplies, isRu);
                          },
                        ),
                      ),
                    ),
          ),

          // Replying To Banner
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF282828),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, size: 16, color: Color(0xFFD2D7DF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${isRu ? "Ответ для" : "Replying to"} @${_replyingTo!.username}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF242424),
              border: Border(top: BorderSide(color: Color(0xFF333333))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _postComment(isRu),
                    decoration: InputDecoration(
                      hintText: _replyingTo != null
                        ? '${isRu ? "Ответить" : "Reply to"} @${_replyingTo!.username}...'
                        : (isRu ? 'Написать комментарий...' : 'Write a comment...'),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF8A897C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isPosting ? null : () => _postComment(isRu),
                  icon: _isPosting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentTile(CommentItem comment, List<CommentItem> replies, bool isRu) {
    final isLiked = comment.userVote == 1;
    final isDisliked = comment.userVote == -1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF3E3E3E),
                backgroundImage: comment.userAvatar.isNotEmpty ? CachedNetworkImageProvider(comment.userAvatar) : null,
                child: comment.userAvatar.isEmpty
                  ? Text(
                      comment.username.isNotEmpty ? comment.username[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.username,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                        if (comment.postPage != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A3A3A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${isRu ? "Стр." : "P."} ${comment.postPage}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFFBDBBB0)),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          _formatDate(comment.createdAt),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      comment.text,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFEEEEEE), height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    // Action Buttons (Upvote, Downvote, Reply)
                    Row(
                      children: [
                        // Upvote
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _vote(comment, 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  isLiked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                                  size: 15,
                                  color: isLiked ? Colors.greenAccent : const Color(0xFFAAAAAA),
                                ),
                                if (comment.votesUp > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '${comment.votesUp}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isLiked ? Colors.greenAccent : const Color(0xFFAAAAAA),
                                      fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Downvote
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _vote(comment, -1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  isDisliked ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
                                  size: 15,
                                  color: isDisliked ? Colors.redAccent : const Color(0xFFAAAAAA),
                                ),
                                if (comment.votesDown > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '${comment.votesDown}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDisliked ? Colors.redAccent : const Color(0xFFAAAAAA),
                                      fontWeight: isDisliked ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Reply
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _replyingTo = comment),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.reply_rounded, size: 15, color: Color(0xFFAAAAAA)),
                                const SizedBox(width: 4),
                                Text(
                                  isRu ? 'Ответить' : 'Reply',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Replies list
          if (replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 10),
              child: Column(
                children: replies.map((r) => _buildReplyTile(r, isRu)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyTile(CommentItem reply, bool isRu) {
    final isLiked = reply.userVote == 1;
    final isDisliked = reply.userVote == -1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF3E3E3E),
            backgroundImage: reply.userAvatar.isNotEmpty ? CachedNetworkImageProvider(reply.userAvatar) : null,
            child: reply.userAvatar.isEmpty
              ? Text(
                  reply.username.isNotEmpty ? reply.username[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                )
              : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      reply.username,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                    ),
                    Text(
                      _formatDate(reply.createdAt),
                      style: const TextStyle(fontSize: 10, color: Color(0xFF888888)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reply.text,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFDDDDDD), height: 1.3),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _vote(reply, 1),
                      child: Icon(
                        isLiked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                        size: 14,
                        color: isLiked ? Colors.greenAccent : const Color(0xFFAAAAAA),
                      ),
                    ),
                    if (reply.votesUp > 0) ...[
                      const SizedBox(width: 4),
                      Text('${reply.votesUp}', style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA))),
                    ],
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => _vote(reply, -1),
                      child: Icon(
                        isDisliked ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
                        size: 14,
                        color: isDisliked ? Colors.redAccent : const Color(0xFFAAAAAA),
                      ),
                    ),
                    if (reply.votesDown > 0) ...[
                      const SizedBox(width: 4),
                      Text('${reply.votesDown}', style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA))),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'только что';
      if (diff.inHours < 1) return '${diff.inMinutes} мин. назад';
      if (diff.inDays < 1) return '${diff.inHours} ч. назад';
      if (diff.inDays < 30) return '${diff.inDays} дн. назад';
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

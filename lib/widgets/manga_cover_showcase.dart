import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mangaloader/theme/app_tokens.dart';

/// A rotatable cover card for a single title, opened from the details header.
/// It gives normal manga covers the same tactile treatment as collectible
/// achievement cards without touching list scrolling.
class MangaCoverShowcase extends StatefulWidget {
  const MangaCoverShowcase({
    super.key,
    required this.title,
    required this.coverUrl,
    required this.rating,
    required this.isRu,
  });

  final String title;
  final String coverUrl;
  final String rating;
  final bool isRu;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String coverUrl,
    required String rating,
    required bool isRu,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MangaCoverShowcase(
        title: title,
        coverUrl: coverUrl,
        rating: rating,
        isRu: isRu,
      ),
    );
  }

  @override
  State<MangaCoverShowcase> createState() => _MangaCoverShowcaseState();
}

class _MangaCoverShowcaseState extends State<MangaCoverShowcase>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cardKey = GlobalKey();
  late final AnimationController _reset;
  double _rotX = 0;
  double _rotY = 0;
  double _startX = 0;
  double _startY = 0;
  Offset _dragStart = Offset.zero;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _reset = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
    _reset.addListener(() {
      final t = Curves.easeOutCubic.transform(_reset.value);
      setState(() {
        _rotX = _startX * (1 - t);
        _rotY = _startY * (1 - t);
      });
    });
  }

  @override
  void dispose() {
    _reset.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _reset.stop();
    _dragStart = details.localPosition;
    _startX = _rotX;
    _startY = _rotY;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final delta = details.localPosition - _dragStart;
    setState(() {
      _rotX = (_startX - delta.dy / 260).clamp(-0.35, 0.35);
      _rotY = (_startY + delta.dx / 260).clamp(-0.35, 0.35);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _startX = _rotX;
    _startY = _rotY;
    _reset.forward(from: 0);
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.png');
          await file.writeAsBytes(bytes.buffer.asUint8List());
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path)],
              text: widget.isRu ? 'Обложка «${widget.title}» в MangaLoader' : '${widget.title} cover in MangaLoader',
            ),
          );
          return;
        }
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratingValue = double.tryParse(widget.rating) ?? 0;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0014)
                        ..rotateX(-_rotX)
                        ..rotateY(_rotY),
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: Container(
                          width: 264,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF242424), Color(0xFF151515)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF3E3E3E)),
                            boxShadow: const [
                              BoxShadow(color: Color(0x55000000), blurRadius: 22, offset: Offset(0, 10)),
                            ],
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: 236,
                                  height: 330,
                                  child: widget.coverUrl.isEmpty
                                      ? const ColoredBox(
                                          color: AppTokens.surfaceRaised,
                                          child: Icon(Icons.broken_image_rounded, color: AppTokens.textSecondary),
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: widget.coverUrl,
                                          httpHeaders: const {'Referer': 'https://mangalib.org/'},
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => const ColoredBox(color: AppTokens.surfaceRaised),
                                          errorWidget: (_, __, ___) => const ColoredBox(
                                            color: AppTokens.surfaceRaised,
                                            child: Icon(Icons.broken_image_rounded, color: AppTokens.textSecondary),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (ratingValue > 0) ...[
                                    const Icon(Icons.star_rounded, size: 16, color: Colors.amberAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.rating,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.isRu ? 'Потяните обложку, чтобы повернуть' : 'Drag the cover to rotate it',
                    style: const TextStyle(color: Color(0xFF7D7D7D), fontSize: 11),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.share_rounded, size: 18),
                    label: Text(widget.isRu ? 'Поделиться обложкой' : 'Share cover'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
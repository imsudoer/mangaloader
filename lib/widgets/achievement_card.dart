import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mangaloader/l10n/strings/achievements_strings.dart';
import 'package:mangaloader/models/achievement.dart';

class _CardSkin {
  const _CardSkin({
    required this.gradient,
    required this.text,
    required this.secondary,
    required this.border,
    required this.glow,
    required this.light,
  });

  final List<Color> gradient;
  final Color text;
  final Color secondary;
  final Color border;
  final Color glow;
  final bool light;

  static _CardSkin of(AchievementMaterial material) {
    switch (material) {
      case AchievementMaterial.paper:
        return const _CardSkin(
          gradient: [Color(0xFFE9D8BC), Color(0xFFCDB291)],
          text: Color(0xFF2B2118),
          secondary: Color(0xFF6B5A45),
          border: Color(0xFFB79A78),
          glow: Color(0x33A67C52),
          light: true,
        );
      case AchievementMaterial.plastic:
        return const _CardSkin(
          gradient: [Color(0xFFF4F6F9), Color(0xFFB9C0CC)],
          text: Color(0xFF1D2530),
          secondary: Color(0xFF5B6575),
          border: Color(0xFF98A2B3),
          glow: Color(0x33C7D0DE),
          light: true,
        );
      case AchievementMaterial.metal:
        return const _CardSkin(
          gradient: [Color(0xFFFFE7A3), Color(0xFFD8A93B), Color(0xFF9C6B12)],
          text: Color(0xFF2B1C00),
          secondary: Color(0xFF6E4A08),
          border: Color(0xFFB9851D),
          glow: Color(0x55FFC83D),
          light: true,
        );
      case AchievementMaterial.holographic:
        return const _CardSkin(
          gradient: [Color(0xFF251343), Color(0xFF1B2C5C), Color(0xFF0C0E22)],
          text: Color(0xFFF7F4FF),
          secondary: Color(0xFFC8BEEA),
          border: Color(0xFF9D7BFF),
          glow: Color(0x669D7BFF),
          light: false,
        );
      case AchievementMaterial.diamond:
        return const _CardSkin(
          gradient: [Color(0xFF0A1424), Color(0xFF102A3E), Color(0xFF070D18)],
          text: Color(0xFFF2FBFF),
          secondary: Color(0xFFA8D8EA),
          border: Color(0xFF7BE8FF),
          glow: Color(0x667BE8FF),
          light: false,
        );
    }
  }
}

class AchievementCardFace extends StatelessWidget {
  const AchievementCardFace({
    super.key,
    required this.achievement,
    required this.isRu,
    this.compact = true,
    this.shine = 0,
  });

  final Achievement achievement;
  final bool isRu;
  final bool compact;
  final double shine;

  String _materialLabel(AchievementsStrings s) {
    switch (achievement.material) {
      case AchievementMaterial.paper:
        return s.materialPaper;
      case AchievementMaterial.plastic:
        return s.materialPlastic;
      case AchievementMaterial.metal:
        return s.materialMetal;
      case AchievementMaterial.holographic:
        return s.materialHolo;
      case AchievementMaterial.diamond:
        return s.materialDiamond;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AchievementsStrings(isRu);
    final skin = _CardSkin.of(achievement.material);
    final hidden = achievement.isSecret && !achievement.isUnlocked;
    final title = hidden ? s.secretTitle : (isRu ? achievement.titleRu : achievement.titleEn);
    final description = hidden
        ? (isRu ? achievement.hintRu : achievement.hintEn)
        : (isRu ? achievement.descRu : achievement.descEn);
    final progress = achievement.progressRatio;
    final showProgress = !achievement.isUnlocked && achievement.maxProgress > 1;

    if (compact) {
      return _buildCompact(s, skin, hidden, title, description);
    }

    final padding = compact ? 10.0 : 18.0;
    final artHeight = compact ? 68.0 : 124.0;
    final artWidth = compact ? 52.0 : 92.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: skin.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 16 : 24),
        border: Border.all(color: skin.border.withValues(alpha: 0.9), width: 1.1),
        boxShadow: [
          BoxShadow(color: skin.glow, blurRadius: compact ? 10 : 24, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 15 : 23),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MaterialPainter(
                  material: achievement.material,
                  light: skin.light,
                  accent: skin.border,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1 + shine, -1),
                      end: Alignment(1 + shine, 1),
                      colors: const [
                        Color(0x00FFFFFF),
                        Color(0x2AFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: const [0.15, 0.5, 0.85],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 2 : 3),
                        decoration: BoxDecoration(
                          color: skin.text.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: skin.border.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          _materialLabel(s),
                          style: TextStyle(
                            color: skin.secondary,
                            fontSize: compact ? 7.5 : 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (achievement.isUnlocked) ...[
                        Icon(
                          Icons.check_circle_rounded,
                          size: compact ? 11 : 14,
                          color: skin.light ? const Color(0xFF2E7D32) : const Color(0xFF8CF7C4),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '+${achievement.xp} XP',
                        style: TextStyle(
                          color: skin.secondary,
                          fontSize: compact ? 8.5 : 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  Center(
                    child: !hidden && achievement.titleCoverUrl != null && achievement.titleCoverUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(compact ? 8 : 12),
                            child: SizedBox(
                              width: artWidth,
                              height: artHeight,
                              child: CachedNetworkImage(
                                imageUrl: achievement.titleCoverUrl!,
                                httpHeaders: const {'Referer': 'https://mangalib.org/'},
                                fit: BoxFit.cover,
                                placeholder: (_, __) => ColoredBox(color: skin.text.withValues(alpha: 0.1)),
                                errorWidget: (_, __, ___) => Icon(Icons.broken_image_rounded, color: skin.secondary, size: 18),
                              ),
                            ),
                          )
                        : Container(
                            width: artWidth,
                            height: artHeight,
                            decoration: BoxDecoration(
                              color: skin.text.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(compact ? 9 : 14),
                              border: Border.all(color: skin.border.withValues(alpha: 0.45)),
                            ),
                            child: Icon(
                              hidden ? Icons.lock_rounded : achievement.icon,
                              size: compact ? 26 : 42,
                              color: hidden ? skin.secondary : skin.text,
                            ),
                          ),
                  ),
                  SizedBox(height: compact ? 9 : 16),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: skin.text,
                      fontSize: compact ? 11.5 : 19,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    SizedBox(height: compact ? 4 : 7),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: skin.secondary,
                        fontSize: compact ? 8.5 : 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (showProgress) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: compact ? 4 : 6,
                        backgroundColor: skin.text.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(skin.border),
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 6),
                    Text(
                      s.progressOf('${achievement.currentProgress}', '${achievement.maxProgress}'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: skin.secondary, fontSize: compact ? 8 : 10.5),
                    ),
                  ] else if (achievement.isUnlocked)
                    Center(
                      child: Text(
                        s.unlockedLabel.toUpperCase(),
                        style: TextStyle(
                          color: skin.secondary,
                          fontSize: compact ? 7.5 : 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Text(
                        s.lockedLabel.toUpperCase(),
                        style: TextStyle(
                          color: skin.secondary,
                          fontSize: compact ? 7.5 : 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(
    AchievementsStrings s,
    _CardSkin skin,
    bool hidden,
    String title,
    String description,
  ) {
    final hasCover = !hidden &&
        achievement.titleCoverUrl != null &&
        achievement.titleCoverUrl!.isNotEmpty;
    final artWidth = hasCover ? 50.0 : 46.0;
    final artHeight = hasCover ? 66.0 : 46.0;
    final art = hasCover
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: artWidth,
              height: artHeight,
              child: CachedNetworkImage(
                imageUrl: achievement.titleCoverUrl!,
                httpHeaders: const {'Referer': 'https://mangalib.org/'},
                fit: BoxFit.cover,
                placeholder: (_, __) => ColoredBox(color: skin.text.withValues(alpha: 0.1)),
                errorWidget: (_, __, ___) => Icon(Icons.broken_image_rounded, color: skin.secondary, size: 18),
              ),
            ),
          )
        : Container(
            width: artWidth,
            height: artHeight,
            decoration: BoxDecoration(
              color: skin.text.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: skin.border.withValues(alpha: 0.35)),
            ),
            child: Icon(
              hidden ? Icons.lock_rounded : achievement.icon,
              size: 21,
              color: hidden ? skin.secondary : skin.text,
            ),
          );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: skin.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.border.withValues(alpha: 0.9), width: 1.1),
        boxShadow: [
          BoxShadow(color: skin.glow, blurRadius: 10, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MaterialPainter(
                  material: achievement.material,
                  light: skin.light,
                  accent: skin.border,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: skin.text.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: skin.border.withValues(alpha: 0.55)),
                        ),
                        child: Text(
                          _materialLabel(s),
                          style: TextStyle(
                            color: skin.secondary,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      if (achievement.titleSlug != null) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.auto_stories_rounded, size: 10, color: skin.secondary),
                      ],
                      const Spacer(),
                      if (achievement.isUnlocked) ...[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 11,
                          color: skin.light ? const Color(0xFF2E7D32) : const Color(0xFF8CF7C4),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '+${achievement.xp} XP',
                        style: TextStyle(
                          color: skin.secondary,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      art,
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: skin.text,
                                fontSize: 12,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: skin.secondary,
                                  fontSize: 8.5,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (achievement.isUnlocked)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 10,
                          color: skin.light ? const Color(0xFF2E7D32) : const Color(0xFF8CF7C4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          s.unlockedLabel.toUpperCase(),
                          style: TextStyle(
                            color: skin.secondary,
                            fontSize: 7.5,
                            letterSpacing: 0.9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    )
                  else if (achievement.maxProgress > 1) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: achievement.progressRatio,
                        minHeight: 4,
                        backgroundColor: skin.text.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(skin.border),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.progressOf('${achievement.currentProgress}', '${achievement.maxProgress}'),
                      style: TextStyle(color: skin.secondary, fontSize: 8),
                    ),
                  ] else
                    Text(
                      s.lockedLabel.toUpperCase(),
                      style: TextStyle(
                        color: skin.secondary,
                        fontSize: 7.5,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AchievementGridCard extends StatelessWidget {
  const AchievementGridCard({
    super.key,
    required this.achievement,
    required this.isRu,
    required this.onTap,
  });

  final Achievement achievement;
  final bool isRu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: RepaintBoundary(
        child: AchievementCardFace(achievement: achievement, isRu: isRu),
      ),
    );
  }
}

class AchievementDetailSheet extends StatefulWidget {
  const AchievementDetailSheet({super.key, required this.achievement, required this.isRu});

  final Achievement achievement;
  final bool isRu;

  static Future<void> show(BuildContext context, Achievement achievement, bool isRu) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AchievementDetailSheet(achievement: achievement, isRu: isRu),
    );
  }

  @override
  State<AchievementDetailSheet> createState() => _AchievementDetailSheetState();
}

class _AchievementDetailSheetState extends State<AchievementDetailSheet>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cardKey = GlobalKey();
  late final AnimationController _resetController;
  Offset _rotation = Offset.zero;
  Offset _dragStart = Offset.zero;
  Offset _startRotation = Offset.zero;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
    _resetController.addListener(() {
      final value = _resetController.value;
      setState(() => _rotation = _startRotation * (1 - value));
    });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _resetController.stop();
    _dragStart = details.localPosition;
    _startRotation = _rotation;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final delta = details.localPosition - _dragStart;
    setState(() {
      _rotation = Offset(
        (_startRotation.dx + delta.dy / 220).clamp(-0.32, 0.32),
        (_startRotation.dy + delta.dx / 220).clamp(-0.32, 0.32),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _startRotation = _rotation;
    _resetController.forward(from: 0);
  }

  Future<void> _share() async {
    final s = AchievementsStrings(widget.isRu);
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/achievement_${widget.achievement.id}_${DateTime.now().millisecondsSinceEpoch}.png');
          await file.writeAsBytes(bytes.buffer.asUint8List());
          await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)], text: s.shareText(
              widget.isRu ? widget.achievement.titleRu : widget.achievement.titleEn,
              widget.isRu ? widget.achievement.descRu : widget.achievement.descEn,
              '${widget.achievement.xp}',
            )),
          );
          return;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.exportFailed)));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AchievementsStrings(widget.isRu);
    final a = widget.achievement;
    final hidden = a.isSecret && !a.isUnlocked;
    final title = hidden ? s.secretTitle : (widget.isRu ? a.titleRu : a.titleEn);

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
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
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                        ..rotateX(-_rotation.dx)
                        ..rotateY(_rotation.dy),
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: SizedBox(
                          width: 300,
                          height: 444,
                          child: AchievementCardFace(
                            achievement: a,
                            isRu: widget.isRu,
                            compact: false,
                            shine: _rotation.dy * 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s.rotateHint,
                    style: const TextStyle(color: Color(0xFF7D7D7D), fontSize: 11),
                  ),
                  if (!a.isUnlocked && a.maxProgress > 1) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: a.progressRatio,
                        minHeight: 7,
                        backgroundColor: const Color(0xFF2A2A2A),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB8B5A4)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.progressOf('${a.currentProgress}', '${a.maxProgress}'),
                      style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB8B5A4),
                      foregroundColor: const Color(0xFF111111),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.share_rounded, size: 18),
                    label: Text(s.shareCard, style: const TextStyle(fontWeight: FontWeight.bold)),
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

class _MaterialPainter extends CustomPainter {
  const _MaterialPainter({required this.material, required this.light, required this.accent});

  final AchievementMaterial material;
  final bool light;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    switch (material) {
      case AchievementMaterial.paper:
        paint
          ..color = Colors.black.withValues(alpha: 0.035)
          ..strokeWidth = 0.8;
        for (double y = 14; y < size.height; y += 13) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        canvas.drawLine(
          Offset(size.width * 0.08, 0),
          Offset(size.width * 0.08, size.height),
          Paint()
            ..color = accent.withValues(alpha: 0.12)
            ..strokeWidth = 1,
        );
      case AchievementMaterial.plastic:
        paint
          ..color = Colors.white.withValues(alpha: 0.16)
          ..strokeWidth = 16;
        canvas.drawLine(Offset(-size.height, size.height), Offset(size.width * 0.7, -size.height * 0.2), paint);
      case AchievementMaterial.metal:
        paint
          ..color = Colors.white.withValues(alpha: 0.12)
          ..strokeWidth = 1;
        for (double x = -size.height; x < size.width; x += 7) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
      case AchievementMaterial.holographic:
        final shader = const LinearGradient(
          colors: [Color(0x337CF7FF), Color(0x33FF7AD9), Color(0x33FFE86A), Color(0x337B8CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size);
        canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
        paint
          ..color = Colors.white.withValues(alpha: 0.10)
          ..strokeWidth = 0.8;
        for (double x = -size.height; x < size.width; x += 26) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
      case AchievementMaterial.diamond:
        paint
          ..color = const Color(0xFF7BE8FF).withValues(alpha: 0.18)
          ..strokeWidth = 0.9;
        final path = Path()
          ..moveTo(0, size.height * 0.25)
          ..lineTo(size.width * 0.5, 0)
          ..lineTo(size.width, size.height * 0.32)
          ..lineTo(size.width * 0.62, size.height)
          ..lineTo(size.width * 0.18, size.height * 0.88)
          ..close();
        canvas.drawPath(path, paint);
        final sparkle = Paint()..color = Colors.white.withValues(alpha: 0.45);
        for (var i = 0; i < 7; i++) {
          final x = size.width * (0.12 + i * 0.13);
          final y = size.height * (0.15 + (i % 4) * 0.2);
          canvas.drawCircle(Offset(x, y), i.isEven ? 1.3 : 0.8, sparkle);
        }
        final glow = Paint()
          ..shader = ui.Gradient.radial(
            Offset(size.width * 0.75, size.height * 0.2),
            size.width * 0.7,
            [const Color(0x337BE8FF), const Color(0x007BE8FF)],
          );
        canvas.drawRect(Offset.zero & size, glow);
    }
  }

  @override
  bool shouldRepaint(_MaterialPainter oldDelegate) =>
      oldDelegate.material != material || oldDelegate.accent != accent;
}
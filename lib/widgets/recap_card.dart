import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mangaloader/l10n/strings/recap_strings.dart';
import 'package:mangaloader/src/rust/api/models.dart';

enum RecapStylePreset { night, paper, neon, kimono }

enum RecapLayout { poster, dossier, timeline }

class RecapPalette {
  const RecapPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.chip,
    required this.border,
    required this.track,
    required this.glow,
    required this.isLight,
  });

  final List<Color> background;
  final List<Color> surface;
  final Color text;
  final Color textSecondary;
  final Color accent;
  final Color chip;
  final Color border;
  final Color track;
  final Color glow;
  final bool isLight;

  static RecapPalette of(RecapStylePreset style) {
    switch (style) {
      case RecapStylePreset.night:
        return const RecapPalette(
          background: [Color(0xFF2A2A2A), Color(0xFF151515)],
          surface: [Color(0xFF242424), Color(0xFF181818)],
          text: Colors.white,
          textSecondary: Color(0xFFBDBBB0),
          accent: Color(0xFFC9C5B2),
          chip: Color(0xFF2E2E2E),
          border: Color(0xFF3E3E3E),
          track: Color(0xFF333333),
          glow: Color(0x22000000),
          isLight: false,
        );
      case RecapStylePreset.paper:
        return const RecapPalette(
          background: [Color(0xFFFFFCF4), Color(0xFFEDE2CC)],
          surface: [Color(0xFFFFFDF8), Color(0xFFF2E8D7)],
          text: Color(0xFF2B2620),
          textSecondary: Color(0xFF776B58),
          accent: Color(0xFFA15532),
          chip: Color(0xFFEAE0CC),
          border: Color(0xFFD7C9B1),
          track: Color(0xFFE5D9C3),
          glow: Color(0x22000000),
          isLight: true,
        );
      case RecapStylePreset.neon:
        return const RecapPalette(
          background: [Color(0xFF0B0B1A), Color(0xFF070711)],
          surface: [Color(0xFF141428), Color(0xFF0B0B1A)],
          text: Color(0xFFF2F4FF),
          textSecondary: Color(0xFF97A3CC),
          accent: Color(0xFF6AF7C8),
          chip: Color(0xFF1D2242),
          border: Color(0xFF2F3B69),
          track: Color(0xFF1C2444),
          glow: Color(0x556AF7C8),
          isLight: false,
        );
      case RecapStylePreset.kimono:
        return const RecapPalette(
          background: [Color(0xFF2A1411), Color(0xFF130908)],
          surface: [Color(0xFF2E1714), Color(0xFF1B0D0C)],
          text: Color(0xFFF8EDE0),
          textSecondary: Color(0xFFC9B29A),
          accent: Color(0xFFE3B15C),
          chip: Color(0xFF3B211B),
          border: Color(0xFF57312A),
          track: Color(0xFF3B221C),
          glow: Color(0x33E3B15C),
          isLight: false,
        );
    }
  }
}

/// Recap card used for the preview and the exported image.
class RecapCard extends StatelessWidget {
  const RecapCard({
    super.key,
    required this.data,
    required this.topManga,
    required this.style,
    required this.layout,
    required this.width,
    required this.isRu,
    this.username,
  });

  final MangaRecapData data;
  final List<RecapMangaItem> topManga;
  final RecapStylePreset style;
  final RecapLayout layout;
  final double width;
  final bool isRu;
  final String? username;

  String _hours(double value) {
    if (value >= 100) return '${value.round()}';
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0') ? rounded.substring(0, rounded.length - 2) : rounded;
  }

  @override
  Widget build(BuildContext context) {
    final s = RecapStrings(isRu);
    final palette = RecapPalette.of(style);
    final year = DateTime.now().year;

    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette.background,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: palette.glow,
            blurRadius: 22,
            spreadRadius: style == RecapStylePreset.neon ? 2 : 0,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RecapPatternPainter(
                    style: style,
                    color: palette.isLight ? palette.text : Colors.white,
                    accent: palette.accent,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(s, palette, year),
                  const SizedBox(height: 18),
                  if (layout == RecapLayout.poster) ..._poster(s, palette) else if (layout == RecapLayout.dossier) ..._dossier(s, palette) else ..._timeline(s, palette),
                  const SizedBox(height: 18),
                  _footer(s, palette, year),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(RecapStrings s, RecapPalette p, int year) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: p.isLight ? 0.16 : 0.20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.accent.withValues(alpha: 0.45)),
          ),
          child: Icon(Icons.menu_book_rounded, size: 20, color: p.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MANGA LOADER',
                style: TextStyle(
                  color: p.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
              Text(
                username?.isNotEmpty == true ? username! : s.summaryFallback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: p.chip,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.border),
          ),
          child: Text(
            '$year',
            style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  List<Widget> _poster(RecapStrings s, RecapPalette p) {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.chaptersReadTitle.toUpperCase(),
                  style: TextStyle(color: p.textSecondary, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.totalChaptersRead}',
                  style: TextStyle(color: p.text, fontSize: 44, height: 0.95, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          _sideFact(value: _hours(data.estimatedReadingHours), label: s.hoursTitle, palette: p),
          const SizedBox(width: 14),
          _sideFact(value: '${data.maxStreak}', label: s.maxStreakTitle, palette: p),
        ],
      ),
      const SizedBox(height: 16),
      _statsGrid(s, p),
      if (data.topGenres.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(s.favoriteGenres, p),
        const SizedBox(height: 8),
        _genreBars(p),
      ],
      if (topManga.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(s.topReadManga, p),
        const SizedBox(height: 8),
        _mangaShelf(p, count: 3),
      ],
      if (_hasTimeOfDay) ...[
        const SizedBox(height: 16),
        _timeOfDay(s, p, compact: true),
      ],
    ];
  }

  List<Widget> _dossier(RecapStrings s, RecapPalette p) {
    final hero = topManga.isNotEmpty ? topManga.first : null;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hero != null)
            _cover(hero, p, width: 78, height: 108)
          else
            Container(
              width: 78,
              height: 108,
              decoration: BoxDecoration(
                color: p.chip,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.border),
              ),
              child: Icon(Icons.auto_stories_rounded, color: p.textSecondary, size: 26),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hero != null
                      ? (hero.rusName.isNotEmpty ? hero.rusName : hero.name)
                      : s.summaryFallback,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 18, height: 1.15, fontWeight: FontWeight.w900),
                ),
                if (hero != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.chapters('${hero.chaptersRead}'),
                    style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: data.topGenres
                      .take(3)
                      .map((g) => _genreChip(g.name, p))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _statRows(s, p),
      if (_hasTimeOfDay) ...[
        const SizedBox(height: 16),
        _timeOfDay(s, p),
      ],
      if (topManga.length > 1) ...[
        const SizedBox(height: 18),
        _sectionTitle(s.topReadManga, p),
        const SizedBox(height: 8),
        _mangaShelf(p, count: 4),
      ],
    ];
  }

  List<Widget> _timeline(RecapStrings s, RecapPalette p) {
    return [
      _timelineSection(
        p,
        index: '01',
        title: s.chaptersReadTitle,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${data.totalChaptersRead}',
              style: TextStyle(color: p.text, fontSize: 38, height: 0.95, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  s.chaptersReadTitle.toLowerCase(),
                  style: TextStyle(color: p.textSecondary, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
      _timelineSection(
        p,
        index: '02',
        title: s.hoursTitle,
        child: _statsGrid(s, p, twoColumns: true),
      ),
      if (data.topGenres.isNotEmpty)
        _timelineSection(
          p,
          index: '03',
          title: s.favoriteGenres,
          child: _genreBars(p),
        ),
      if (_hasTimeOfDay)
        _timelineSection(
          p,
          index: '04',
          title: s.timeOfDayTitle,
          child: _timeOfDay(s, p),
        ),
      if (topManga.isNotEmpty)
        _timelineSection(
          p,
          index: '05',
          title: s.topReadManga,
          child: _mangaShelf(p, count: 3),
        ),
    ];
  }

  Widget _timelineSection(
    RecapPalette p, {
    required String index,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(
                index,
                style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
              ),
              Container(width: 1, height: 28, color: p.border),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: TextStyle(color: p.textSecondary, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(RecapStrings s, RecapPalette p, {bool twoColumns = false}) {
    final tiles = [
      _StatTileData(Icons.pages_rounded, s.pagesReadTitle, '${data.totalPagesRead}', p),
      _StatTileData(Icons.timer_outlined, s.hoursTitle, _hours(data.estimatedReadingHours), p),
      _StatTileData(Icons.calendar_month_rounded, s.activeDaysTitle, '${data.activeDaysCount}', p),
      _StatTileData(Icons.local_fire_department_rounded, s.maxStreakTitle, '${data.maxStreak}', p),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: twoColumns ? 1.7 : 1.55,
      children: tiles.map((t) => _statTile(t, p)).toList(),
    );
  }

  Widget _statTile(_StatTileData t, RecapPalette p) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: p.chip.withValues(alpha: p.isLight ? 0.55 : 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(t.icon, size: 15, color: p.accent),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: 18, height: 1, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                t.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary, fontSize: 9.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statRows(RecapStrings s, RecapPalette p) {
    final rows = [
      (s.chaptersReadTitle, '${data.totalChaptersRead}'),
      (s.pagesReadTitle, '${data.totalPagesRead}'),
      (s.hoursTitle, _hours(data.estimatedReadingHours)),
      (s.activeDaysTitle, '${data.activeDaysCount}'),
      (s.maxStreakTitle, '${data.maxStreak}'),
    ];
    return Column(
      children: rows
          .map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Text(row.$1, style: TextStyle(color: p.textSecondary, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(child: Container(height: 1, color: p.border)),
                    const SizedBox(width: 8),
                    Text(
                      row.$2,
                      style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _sideFact({required String value, required String label, required RecapPalette palette}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: TextStyle(color: palette.text, fontSize: 17, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(color: palette.textSecondary, fontSize: 9)),
      ],
    );
  }

  Widget _sectionTitle(String text, RecapPalette p) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(color: p.textSecondary, fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w800),
    );
  }

  Widget _genreBars(RecapPalette p) {
    return Column(
      children: data.topGenres.take(3).map((g) {
        final value = (g.percentage / 100).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${g.percentage.toStringAsFixed(1)}%',
                    style: TextStyle(color: p.accent, fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: p.track,
                  valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _genreChip(String name, RecapPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: p.isLight ? 0.12 : 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Text(name, style: TextStyle(color: p.accent, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _mangaShelf(RecapPalette p, {required int count}) {
    final items = topManga.take(count).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _coverItems(items[i], p)),
        ],
      ],
    );
  }

  Widget _coverItems(RecapMangaItem item, RecapPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cover(item, p, width: double.infinity, height: 82),
        const SizedBox(height: 5),
        Text(
          item.rusName.isNotEmpty ? item.rusName : item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.text, fontSize: 9.5, height: 1.2, fontWeight: FontWeight.w600),
        ),
        Text(
          '${item.chaptersRead}',
          style: TextStyle(color: p.accent, fontSize: 9, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _cover(RecapMangaItem item, RecapPalette p, {required double width, required double height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: width,
        height: height,
        color: p.chip,
        child: item.coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: item.coverUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: p.chip),
                errorWidget: (_, __, ___) => Icon(Icons.broken_image_rounded, size: 16, color: p.textSecondary),
              )
            : Icon(Icons.auto_stories_rounded, size: 18, color: p.textSecondary),
      ),
    );
  }

  bool get _hasTimeOfDay {
    final t = data.timeOfDay;
    return t.nightCount + t.morningCount + t.afternoonCount + t.eveningCount > 0;
  }

  Widget _timeOfDay(RecapStrings s, RecapPalette p, {bool compact = false}) {
    final t = data.timeOfDay;
    final counts = [t.nightCount.toInt(), t.morningCount.toInt(), t.afternoonCount.toInt(), t.eveningCount.toInt()];
    final total = counts.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();
    final labels = [s.nightLabel, s.morningLabel, s.dayLabel, s.eveningLabel];
    final colors = p.isLight
        ? const [Color(0xFF4C5BA8), Color(0xFFD28A2E), Color(0xFF3C8A68), Color(0xFFB2573C)]
        : const [Color(0xFF8796FF), Color(0xFFFFC857), Color(0xFF65D6A6), Color(0xFFFF7A59)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) _sectionTitle(s.timeOfDayTitle, p),
        if (!compact) const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  if (counts[i] > 0) Expanded(flex: counts[i], child: ColoredBox(color: colors[i])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (var i = 0; i < 4; i++)
              if (counts[i] > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(
                      '${labels[i]} ${(counts[i] * 100 / total).round()}%',
                      style: TextStyle(color: p.textSecondary, fontSize: 9),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }

  Widget _footer(RecapStrings s, RecapPalette p, int year) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: p.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'MANGA LOADER · $year',
            style: TextStyle(color: p.textSecondary, fontSize: 8.5, letterSpacing: 0.8, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Container(height: 1, color: p.border)),
      ],
    );
  }
}

class _StatTileData {
  const _StatTileData(this.icon, this.label, this.value, this.palette);
  final IconData icon;
  final String label;
  final String value;
  final RecapPalette palette;
}

class _RecapPatternPainter extends CustomPainter {
  const _RecapPatternPainter({required this.style, required this.color, required this.accent});

  final RecapStylePreset style;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    switch (style) {
      case RecapStylePreset.night:
        paint
          ..color = color.withValues(alpha: 0.035)
          ..strokeWidth = 1;
        for (double x = -size.height; x < size.width; x += 24) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
      case RecapStylePreset.paper:
        paint
          ..color = color.withValues(alpha: 0.055)
          ..strokeWidth = 0.8;
        for (double y = 54; y < size.height; y += 24) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        canvas.drawLine(
          Offset(30, 0),
          Offset(30, size.height),
          Paint()
            ..color = accent.withValues(alpha: 0.14)
            ..strokeWidth = 1,
        );
      case RecapStylePreset.neon:
        paint
          ..color = accent.withValues(alpha: 0.06)
          ..strokeWidth = 0.8;
        for (double x = 0; x < size.width; x += 22) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y < size.height; y += 22) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case RecapStylePreset.kimono:
        paint
          ..color = accent.withValues(alpha: 0.08)
          ..strokeWidth = 1;
        for (double y = size.height * 0.55; y < size.height + 40; y += 20) {
          for (double x = -40; x < size.width + 40; x += 40) {
            canvas.drawArc(Rect.fromCircle(center: Offset(x, y), radius: 18), math.pi, math.pi, false, paint);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_RecapPatternPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color || oldDelegate.accent != accent;
}
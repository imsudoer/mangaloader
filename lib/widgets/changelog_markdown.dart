import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mangaloader/theme/app_tokens.dart';

/// Renders the GitHub release body (a markdown subset) inside the update sheet.
///
/// Release notes are written as `CHANGELOG.md` sections, so headings, bullet lists,
/// bold text, inline code and links are enough. A dedicated widget keeps the styling
/// consistent with the dark sheet instead of pulling a full markdown package.
class ChangelogMarkdown extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color textColor;
  final Color accentColor;

  const ChangelogMarkdown(
    this.data, {
    super.key,
    this.fontSize = 12.5,
    this.textColor = AppTokens.textPrimary,
    this.accentColor = AppTokens.accent,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(data);
    if (blocks.isEmpty) {
      return Text(
        data,
        style: TextStyle(fontSize: fontSize, color: textColor, height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  List<Widget> _parse(String raw) {
    final widgets = <Widget>[];
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final text = paragraph.join(' ').trim();
      paragraph.clear();
      if (text.isEmpty) return;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _inlineText(text, _baseStyle),
      ));
    }

    for (final rawLine in lines) {
      final line = _stripHtml(rawLine).trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      if (RegExp(r'^-{3,}$').hasMatch(trimmed) ||
          RegExp(r'^\*{3,}$').hasMatch(trimmed)) {
        flushParagraph();
        widgets.add(Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 10),
          color: Colors.white12,
        ));
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        final level = heading.group(1)!.length;
        final text = heading.group(2)!.trim();
        widgets.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 10 : 6, bottom: 6),
          child: _inlineText(
            text,
            TextStyle(
              fontSize: level <= 2 ? fontSize + 2.5 : fontSize + 1,
              fontWeight: FontWeight.bold,
              color: level <= 2 ? Colors.white : accentColor,
              height: 1.35,
            ),
          ),
        ));
        continue;
      }

      final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        final indent = (bullet.group(1)!.length / 2).floor();
        final text = _stripHtml(bullet.group(2)!).trim();
        widgets.add(Padding(
          padding: EdgeInsets.only(left: 4.0 + indent * 12, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: _inlineText(text, _baseStyle)),
            ],
          ),
        ));
        continue;
      }

      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${numbered.group(1)}.',
                  style: _baseStyle.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(child: _inlineText(numbered.group(2)!.trim(), _baseStyle)),
            ],
          ),
        ));
        continue;
      }

      final quote = RegExp(r'^>\s?(.*)$').firstMatch(trimmed);
      if (quote != null) {
        flushParagraph();
        widgets.add(Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accentColor, width: 2)),
          ),
          child: _inlineText(quote.group(1)!.trim(), _baseStyle),
        ));
        continue;
      }

      paragraph.add(trimmed);
    }

    flushParagraph();
    return widgets;
  }

  TextStyle get _baseStyle => TextStyle(
        fontSize: fontSize,
        color: textColor,
        height: 1.5,
      );

  /// GitHub bodies sometimes embed raw HTML; the release notes never rely on it.
  String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
  }

  Widget _inlineText(String text, TextStyle style) {
    return Text.rich(
      TextSpan(children: _inlineSpans(text, style)),
    );
  }

  List<InlineSpan> _inlineSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*\n]+\*|_[^_\n]+_|\[[^\]]+\]\([^)]+\))',
    );

    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start), style: base));
      }
      final token = match.group(0)!;

      if (token.startsWith('**') || token.startsWith('__')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
        ));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.white10,
            color: const Color(0xFFE6E1CF),
          ),
        ));
      } else if (token.startsWith('[')) {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token);
        if (link == null) {
          spans.add(TextSpan(text: token, style: base));
        } else {
          final label = link.group(1)!;
          final url = link.group(2)!;
          spans.add(TextSpan(
            text: label,
            style: base.copyWith(
              color: accentColor,
              decoration: TextDecoration.underline,
              decorationColor: accentColor,
            ),
            recognizer: _LaunchRecognizer(url),
          ));
        }
      } else {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      }

      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: base));
    }
    return spans;
  }
}

/// Opens release links. Stateless widgets cannot own a [TapGestureRecognizer] that
/// outlives a frame, so the recognizer is a lightweight, disposable subclass.
class _LaunchRecognizer extends TapGestureRecognizer {
  _LaunchRecognizer(String url) {
    onTap = () async {
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    };
  }
}
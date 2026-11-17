/// MangaLib stores comment bodies as HTML fragments. They routinely contain
/// `<br>`, links, spoilers and site-specific widgets such as
/// `<span class="timecode-node" data-player="Animelib">03:42</span>`. Rendering
/// the raw string leaks tags into the reader, so comment text is reduced to
/// plain text while keeping line breaks and readable characters.
String htmlToPlainText(String input) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  var index = 0;

  while (index < input.length) {
    final char = input[index];

    if (char == '<') {
      if (!_startsTag(input, index + 1)) {
        // A lone "<" is user text (for example "2 < 3"), not markup.
        out.write(char);
        index++;
        continue;
      }
      final close = input.indexOf('>', index + 1);
      if (close == -1) {
        // A lone "<" is user text, not markup.
        out.write(char);
        index++;
        continue;
      }
      final tag = input.substring(index + 1, close).trim().toLowerCase();
      if (tag.startsWith('br')) {
        out.write('\n');
      } else if (tag.startsWith('p') ||
          tag.startsWith('/p') ||
          tag.startsWith('div') ||
          tag.startsWith('/div') ||
          tag.startsWith('li') ||
          tag.startsWith('/li') ||
          tag.startsWith('blockquote') ||
          tag.startsWith('/blockquote')) {
        out.write('\n');
      }
      // Every other tag is markup around text we keep; only the text matters.
      index = close + 1;
      continue;
    }

    if (char == '&') {
      final semicolon = input.indexOf(';', index + 1);
      if (semicolon != -1 && semicolon - index <= 10) {
        final entity = input.substring(index + 1, semicolon);
        final decoded = _decodeEntity(entity);
        if (decoded != null) {
          out.write(decoded);
          index = semicolon + 1;
          continue;
        }
      }
    }

    out.write(char);
    index++;
  }

  return out
      .toString()
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

bool _startsTag(String input, int index) {
  if (index >= input.length) return false;
  final code = input.codeUnitAt(index);
  final isAsciiLetter =
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  final char = input[index];
  return isAsciiLetter || char == '/' || char == '!' || char == '?';
}

String? _decodeEntity(String entity) {
  switch (entity.toLowerCase()) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
    case '#39':
      return "'";
    case 'nbsp':
      return ' ';
    case 'hellip':
      return '…';
    case 'mdash':
      return '—';
    case 'ndash':
      return '–';
  }
  if (entity.startsWith('#x') || entity.startsWith('#X')) {
    final code = int.tryParse(entity.substring(2), radix: 16);
    return code == null ? null : String.fromCharCode(code);
  }
  if (entity.startsWith('#')) {
    final code = int.tryParse(entity.substring(1));
    return code == null ? null : String.fromCharCode(code);
  }
  return null;
}
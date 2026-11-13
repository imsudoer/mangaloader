import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/widgets/changelog_markdown.dart';

String renderedPlainText(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((widget) => widget.text.toPlainText())
      .join('\n');
}

void main() {
  testWidgets('renders headings and bullets without markdown markers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChangelogMarkdown(
          '# Версия 1.9.0\n\n### Читалка\n- **Двойной тап** зум\n- Ленивый список\n',
        ),
      ),
    ));

    final text = renderedPlainText(tester);
    expect(text, contains('Версия 1.9.0'));
    expect(text, contains('Читалка'));
    expect(text, contains('Двойной тап'));
    expect(text, contains('Ленивый список'));
    expect(text, isNot(contains('#')));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('- ')));
  });

  testWidgets('keeps inline code and italic content readable', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChangelogMarkdown('Исправлен `read_cbz_page` и *кэш* архива'),
      ),
    ));

    final text = renderedPlainText(tester);
    expect(text, contains('read_cbz_page'));
    expect(text, contains('кэш'));
    expect(text, isNot(contains('`')));
  });

  testWidgets('drops raw html and decodes entities', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChangelogMarkdown('<b>Важно</b>: A &amp; B<br>вторая строка'),
      ),
    ));

    final text = renderedPlainText(tester);
    expect(text, contains('Важно'));
    expect(text, contains('A & B'));
    expect(text, isNot(contains('<b>')));
  });

  testWidgets('separates sections with a rule instead of dashes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChangelogMarkdown('Первый блок\n\n---\n\nВторой блок'),
      ),
    ));

    expect(renderedPlainText(tester), contains('Первый блок'));
    expect(renderedPlainText(tester), contains('Второй блок'));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxHeight == 1.0,
      ),
      findsOneWidget,
    );
  });
}
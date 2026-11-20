import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/desktop/desktop_layout.dart';

void main() {
  group('DesktopLayout.gridColumns', () {
    test('keeps at least two columns on narrow windows', () {
      expect(DesktopLayout.gridColumns(320), 2);
      expect(DesktopLayout.gridColumns(0), 2);
    });

    test('grows the column count with the available width', () {
      expect(DesktopLayout.gridColumns(760), 4);
      expect(DesktopLayout.gridColumns(1200), 6);
      expect(DesktopLayout.gridColumns(1600), 8);
    });

    test('caps runaway column counts on very wide windows', () {
      expect(DesktopLayout.gridColumns(6000), 12);
    });

    test('guards against non-finite constraints', () {
      expect(DesktopLayout.gridColumns(double.infinity), 2);
      expect(DesktopLayout.gridColumns(double.nan), 2);
    });
  });
}

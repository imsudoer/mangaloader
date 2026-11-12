import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/providers/settings_provider.dart';

void main() {
  group('ReaderPrefs', () {
    test('defaults match the classic webtoon reader', () {
      const prefs = ReaderPrefs();
      expect(prefs.mode, 'vertical');
      expect(prefs.background, 'black');
      expect(prefs.boxFit, 'contain');
      expect(prefs.dualPage, 'auto');
      expect(prefs.tapZones, 'standard');
      expect(prefs.colorFilter, 'none');
      expect(prefs.sharpen, 'off');
      expect(prefs.cropBorders, isFalse);
      expect(prefs.cropPercent, 3.0);
      expect(prefs.brightness, 1.0);
      expect(prefs.autoScrollSpeed, 1.0);
    });

    test('round-trips through JSON', () {
      const prefs = ReaderPrefs(
        mode: 'rtl',
        background: 'darkGrey',
        boxFit: 'fitWidth',
        dualPage: 'dual',
        tapZones: 'inverted',
        colorFilter: 'sepia',
        sharpen: 'high',
        cropBorders: true,
        cropPercent: 7.0,
        brightness: 0.6,
        autoScrollSpeed: 3.5,
      );

      final restored = ReaderPrefs.fromJson(prefs.toJson());
      expect(restored.mode, prefs.mode);
      expect(restored.background, prefs.background);
      expect(restored.boxFit, prefs.boxFit);
      expect(restored.dualPage, prefs.dualPage);
      expect(restored.tapZones, prefs.tapZones);
      expect(restored.colorFilter, prefs.colorFilter);
      expect(restored.sharpen, prefs.sharpen);
      expect(restored.cropBorders, isTrue);
      expect(restored.cropPercent, 7.0);
      expect(restored.brightness, 0.6);
      expect(restored.autoScrollSpeed, 3.5);
    });

    test('corrupt or partial payloads fall back to defaults', () {
      final restored = ReaderPrefs.fromJson(<String, dynamic>{
        'mode': 42,
        'brightness': 'not-a-number',
        'cropBorders': 'yes',
      });

      expect(restored.mode, 'vertical');
      expect(restored.brightness, 1.0);
      expect(restored.cropBorders, isFalse);
    });

    test('copyWith keeps untouched fields', () {
      const prefs = ReaderPrefs(mode: 'rtl', brightness: 0.8);
      final updated = prefs.copyWith(sharpen: 'subtle');
      expect(updated.mode, 'rtl');
      expect(updated.brightness, 0.8);
      expect(updated.sharpen, 'subtle');
    });
  });
}
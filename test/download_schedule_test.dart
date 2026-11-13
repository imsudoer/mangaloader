import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/providers/settings_provider.dart';

void main() {
  group('DownloadSchedule', () {
    test('a plain night window contains the hours inside it', () {
      const schedule = DownloadSchedule(
        enabled: true,
        startHour: 1,
        endHour: 7,
      );
      expect(schedule.contains(DateTime(2026, 11, 13, 0, 59)), isFalse);
      expect(schedule.contains(DateTime(2026, 11, 13, 1, 0)), isTrue);
      expect(schedule.contains(DateTime(2026, 11, 13, 6, 59)), isTrue);
      expect(schedule.contains(DateTime(2026, 11, 13, 7, 0)), isFalse);
    });

    test('a window over midnight wraps around', () {
      const schedule = DownloadSchedule(
        enabled: true,
        startHour: 23,
        endHour: 6,
      );
      expect(schedule.contains(DateTime(2026, 11, 13, 22, 59)), isFalse);
      expect(schedule.contains(DateTime(2026, 11, 13, 23, 30)), isTrue);
      expect(schedule.contains(DateTime(2026, 11, 13, 0, 30)), isTrue);
      expect(schedule.contains(DateTime(2026, 11, 13, 5, 59)), isTrue);
      expect(schedule.contains(DateTime(2026, 11, 13, 6, 0)), isFalse);
    });

    test('a disabled schedule never contains a moment', () {
      const schedule = DownloadSchedule(startHour: 0, endHour: 24);
      expect(schedule.contains(DateTime(2026, 11, 13, 12)), isFalse);
      expect(schedule.nextOpening(DateTime(2026, 11, 13, 12)), isNull);
    });

    test('nextOpening points at today or tomorrow', () {
      const schedule = DownloadSchedule(enabled: true, startHour: 23, endHour: 6);
      expect(
        schedule.nextOpening(DateTime(2026, 11, 13, 12)),
        DateTime(2026, 11, 13, 23),
      );
      expect(
        schedule.nextOpening(DateTime(2026, 11, 14, 0, 30)),
        isNull,
      );
      expect(
        schedule.nextOpening(DateTime(2026, 11, 14, 6, 30)),
        DateTime(2026, 11, 14, 23),
      );
    });

    test('json round trip keeps the window', () {
      const schedule = DownloadSchedule(
        enabled: true,
        startHour: 23,
        endHour: 6,
      );
      final restored = DownloadSchedule.fromJson(schedule.toJson());
      expect(restored.enabled, isTrue);
      expect(restored.startHour, 23);
      expect(restored.endHour, 6);
    });
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/services/update_checker.dart';

void main() {
  group('UpdateChecker.isNewerVersion', () {
    test('detects patch and minor bumps', () {
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.8.3'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.9.0'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.8.2', '2.0.0'), isTrue);
    });

    test('ignores downgrades and equal versions', () {
      expect(UpdateChecker.isNewerVersion('1.9.0', '1.8.9'), isFalse);
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.8.2'), isFalse);
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.8.2+37'), isFalse);
    });

    test('accepts longer or shorter version strings', () {
      expect(UpdateChecker.isNewerVersion('1.8', '1.8.1'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.9'), isTrue);
      expect(UpdateChecker.isNewerVersion('v1.8.2', 'v1.8.3'), isTrue);
    });

    test('prerelease of a newer version still counts as an update', () {
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.8.3-beta.1'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.8.2', '1.9.0-beta.2'), isTrue);
    });

    test('orders prereleases among themselves', () {
      expect(UpdateChecker.isNewerVersion('1.8.3-beta.1', '1.8.3-beta.2'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.8.3-beta.2', '1.8.3-beta.1'), isFalse);
      expect(UpdateChecker.isNewerVersion('1.8.3-beta.2', '1.8.3-beta.10'), isTrue);
    });

    test('final release supersedes its own prereleases', () {
      expect(UpdateChecker.isNewerVersion('1.8.3-beta.2', '1.8.3'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.8.3', '1.8.3-beta.2'), isFalse);
    });

    test('malformed versions never report an update', () {
      expect(UpdateChecker.isNewerVersion('dev-latest', '1.8.3'), isFalse);
      expect(UpdateChecker.isNewerVersion('1.8.2', 'not-a-version'), isFalse);
    });
  });
}
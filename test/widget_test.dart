import 'package:flutter_test/flutter_test.dart';

// A simple placeholder test to ensure `flutter test` does not fail
// with “no tests found” in CI.
void main() {
  group('Basic sanity checks', () {
    test('flutter test runner is alive', () {
      expect(true, isTrue);
    });

    test('arithmetic works', () {
      expect(2 + 2, equals(4));
    });
  });
}

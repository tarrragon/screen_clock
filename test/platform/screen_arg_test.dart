import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/platform/screen_arg.dart';

void main() {
  group('parseScreenArg', () {
    test('returns null when no args', () {
      expect(parseScreenArg(<String>[]), isNull);
    });

    test('returns null when no --screen= argument', () {
      expect(parseScreenArg(<String>['--foo=bar', '-v']), isNull);
    });

    test('parses a valid non-negative integer', () {
      expect(parseScreenArg(<String>['--screen=0']), 0);
      expect(parseScreenArg(<String>['--screen=1']), 1);
      expect(parseScreenArg(<String>['--screen=42']), 42);
    });

    test('returns null for non-integer value', () {
      expect(parseScreenArg(<String>['--screen=abc']), isNull);
    });

    test('returns null for negative value', () {
      expect(parseScreenArg(<String>['--screen=-1']), isNull);
    });

    test('returns null when value missing', () {
      expect(parseScreenArg(<String>['--screen=']), isNull);
    });

    test('last occurrence wins (cli convention)', () {
      expect(parseScreenArg(<String>['--screen=0', '--screen=2']), 2);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/age_formatter.dart';

void main() {
  group('AgeFormatter.format', () {
    test('出生當下年齡為 00 00 00 00 00', () {
      final DateTime birth = DateTime.utc(2000, 1, 1);
      expect(AgeFormatter.format(birth, birth), '00 00 00 00 00');
    });

    test('出生日在未來時夾為 0', () {
      final DateTime birth = DateTime.utc(2000, 1, 1);
      final DateTime now = birth.subtract(const Duration(days: 30));
      expect(AgeFormatter.format(birth, now), '00 00 00 00 00');
    });

    test('整數年齡補成兩位數（個位數補前導零）', () {
      final DateTime birth = DateTime.utc(2000, 1, 1);
      final DateTime now = DateTime.utc(2005, 7, 1); // 約 5.5 歲
      final String result = AgeFormatter.format(birth, now);
      expect(result.startsWith('05 '), isTrue, reason: result);
    });

    test('輸出固定為 5 組，小數 4 組皆為兩位數', () {
      final DateTime birth = DateTime.utc(1990, 3, 15);
      final DateTime now = DateTime.utc(2026, 5, 29, 12, 34, 56);
      final List<String> groups = AgeFormatter.format(birth, now).split(' ');
      expect(groups.length, 5);
      for (int i = 1; i < groups.length; i++) {
        expect(groups[i].length, 2, reason: '第 $i 組應為兩位數: ${groups[i]}');
      }
    });

    test('百歲以上首組為三位數，小數仍為 4 組', () {
      final DateTime birth = DateTime.utc(1900, 1, 1);
      final DateTime now = DateTime.utc(2010, 1, 1); // 約 110 歲
      final List<String> groups = AgeFormatter.format(birth, now).split(' ');
      expect(groups.length, 5);
      expect(groups[0].length, 3, reason: groups[0]);
      expect(groups[0].startsWith('1'), isTrue);
    });

    test('小數位反映已過時間（半年約對應一半年比例）', () {
      // 半個平均年後，年齡小數約為 0.5（首組小數 ≈ 50）。
      final DateTime birth = DateTime.utc(2000, 1, 1);
      final Duration halfYear = Duration(
        microseconds: (365.2425 * Duration.microsecondsPerDay / 2).round(),
      );
      final DateTime now = birth.add(halfYear);
      final List<String> groups = AgeFormatter.format(birth, now).split(' ');
      expect(groups[0], '00');
      expect(groups[1], '50'); // 小數第 1-2 位
    });
  });
}

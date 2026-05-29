import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/age_formatter.dart';
import 'package:screen_clock/app_constants.dart';

void main() {
  // 預期組數 = 年齡 1 組 + 小數每兩位一組。隨 decimalPlaces 自動調整。
  final int expectedGroups = 1 + AppAge.decimalPlaces ~/ 2;
  final String zeroAge =
      List<String>.filled(expectedGroups, '00').join(' ');

  group('AgeFormatter.format', () {
    test('出生當下年齡全為零組', () {
      final DateTime birth = DateTime.utc(2000, 1, 1);
      expect(AgeFormatter.format(birth, birth), zeroAge);
    });

    test('出生日在未來時夾為 0', () {
      final DateTime birth = DateTime.utc(2000, 1, 1);
      final DateTime now = birth.subtract(const Duration(days: 30));
      expect(AgeFormatter.format(birth, now), zeroAge);
    });

    test('整數年齡補成兩位數（個位數補前導零）', () {
      final DateTime birth = DateTime.utc(2000, 1, 1);
      final DateTime now = DateTime.utc(2005, 7, 1); // 約 5.5 歲
      final String result = AgeFormatter.format(birth, now);
      expect(result.startsWith('05 '), isTrue, reason: result);
    });

    test('輸出組數正確，小數各組皆為兩位數', () {
      final DateTime birth = DateTime.utc(1990, 3, 15);
      final DateTime now = DateTime.utc(2026, 5, 29, 12, 34, 56);
      final List<String> groups = AgeFormatter.format(birth, now).split(' ');
      expect(groups.length, expectedGroups);
      for (int i = 1; i < groups.length; i++) {
        expect(groups[i].length, 2, reason: '第 $i 組應為兩位數: ${groups[i]}');
      }
    });

    test('百歲以上首組為三位數，小數組數不變', () {
      final DateTime birth = DateTime.utc(1900, 1, 1);
      final DateTime now = DateTime.utc(2010, 1, 1); // 約 110 歲
      final List<String> groups = AgeFormatter.format(birth, now).split(' ');
      expect(groups.length, expectedGroups);
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

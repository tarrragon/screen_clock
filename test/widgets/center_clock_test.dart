// CenterClock widget tests (SPEC-002).
//
// 涵蓋：
// - formatTime 的 HH:mm:ss 格式（含補零）
// - initState 立即顯示當前時間（不出現 placeholder）
// - dispose 取消 timer（透過 pumpWidget→pumpWidget 切換驗證無 pending timer）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/widgets/center_clock.dart';

void main() {
  group('CenterClock.formatTime', () {
    test('pads single-digit components with leading zero', () {
      expect(
        CenterClock.formatTime(DateTime(2026, 5, 29, 3, 4, 5)),
        '03:04:05',
      );
    });

    test('preserves two-digit components', () {
      expect(
        CenterClock.formatTime(DateTime(2026, 5, 29, 23, 59, 59)),
        '23:59:59',
      );
    });

    test('treats midnight as 00:00:00', () {
      expect(
        CenterClock.formatTime(DateTime(2026, 5, 29, 0, 0, 0)),
        '00:00:00',
      );
    });
  });

  testWidgets('shows current time immediately on first frame',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CenterClock()));
    final Iterable<Text> texts =
        tester.widgetList<Text>(find.byType(Text));
    expect(texts, isNotEmpty);
    final String label = texts.first.data!;
    expect(
      RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(label),
      isTrue,
      reason: 'expected HH:mm:ss, got "$label"',
    );
  });

  testWidgets('disposes timer when widget removed',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CenterClock()));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    // pumpAndSettle would hang if a periodic timer were still active.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });
}

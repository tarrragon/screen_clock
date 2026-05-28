// Smoke test for ScreenClockApp scaffold.
//
// 真正的視窗透明 / click-through 行為需在 macOS 環境手動驗收（見 UC-01/02）。
// 本檔僅驗 widget tree 可正常構建、套用常數背景色。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/main.dart';
import 'package:screen_clock/models/settings_model.dart';

void main() {
  testWidgets('ScreenClockApp builds with transparent scaffold',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenClockApp(settings: SettingsModel.defaults()),
    );

    final scaffoldFinder = find.byType(Scaffold);
    expect(scaffoldFinder, findsOneWidget);
    final Scaffold scaffold = tester.widget<Scaffold>(scaffoldFinder);
    expect(scaffold.backgroundColor, AppColors.overlayBackground);
  });
}

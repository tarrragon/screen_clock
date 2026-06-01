// ScreenClockApp 假全螢幕讓位行為測試（ticket 1.2.1-W2-001）。
//
// 驗證 Dart 端切換邏輯：覆蓋時隱藏 CenterClock，退出後復現。
// 原生 CGWindowList 覆蓋判定須實機 runtime 驗收（acceptance #3）。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/main.dart';
import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/platform/fullscreen_detector.dart';
import 'package:screen_clock/services/auto_launch_service.dart';
import 'package:screen_clock/services/settings_service.dart';
import 'package:screen_clock/state/settings_controller.dart';
import 'package:screen_clock/widgets/center_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;

  setUp(() {
    channel = const MethodChannel(AppFullscreenDetect.channelName);
  });

  Future<void> sendCoverage(bool covered) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        AppFullscreenDetect.onCoverageChangedMethod,
        <String, Object?>{AppFullscreenDetect.coveredArgKey: covered},
      ),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, message, (_) {});
  }

  Future<void> pumpApp(WidgetTester tester) async {
    final SettingsController controller = SettingsController(
      initial: SettingsModel.defaults(),
      service: InMemorySettingsService(),
      autoLaunchService: InMemoryAutoLaunchService(),
    );
    await tester.pumpWidget(
      ScreenClockApp(
        controller: controller,
        availableScreenCount: 1,
        fullscreenDetector: FullscreenDetector(channel: channel),
      ),
    );
  }

  testWidgets('預設顯示時鐘', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.byType(CenterClock), findsOneWidget);
  });

  testWidgets('被假全螢幕覆蓋時隱藏時鐘，退出後復現',
      (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.byType(CenterClock), findsOneWidget);

    await sendCoverage(true);
    await tester.pump();
    expect(find.byType(CenterClock), findsNothing);

    await sendCoverage(false);
    await tester.pump();
    expect(find.byType(CenterClock), findsOneWidget);
  });
}

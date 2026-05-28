import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';
import 'platform/display_detector.dart';
import 'platform/screen_arg.dart';
import 'widgets/center_clock.dart';

final DisplayDetector _detector = DisplayDetector();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await _applyOverlayWindowProperties(args);
  runApp(const ScreenClockApp());
}

/// 依 SPEC-001 + SPEC-003 序列套用所有遮罩視窗屬性。
///
/// 順序：static 屬性 → 解析目標螢幕 → 套用 size/position → show。
/// Hot-plug 監聽於 show 之後啟動，避免初始化途中觸發切換。
Future<void> _applyOverlayWindowProperties(List<String> args) async {
  await windowManager.waitUntilReadyToShow();
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(AppColors.overlayBackground);
  await windowManager.setHasShadow(AppWindow.hasShadow);
  await windowManager.setAlwaysOnTop(AppWindow.isAlwaysOnTop);
  await windowManager.setIgnoreMouseEvents(AppWindow.ignoreMouseEvents);

  final int? requestedIndex = parseScreenArg(args);
  final Display target = await _detector.resolveTargetDisplay(requestedIndex);
  await _coverDisplay(target);
  await windowManager.show();

  _detector.startWatching(
    watchedIndex: requestedIndex ?? 0,
    onTargetLost: _onTargetScreenLost,
  );
}

/// 把視窗鋪到指定螢幕（SPEC-001 FR-01 + SPEC-003 FR-03）。
///
/// 主螢幕（visiblePosition 為 null）直接用 [AppSizes.windowOrigin]；
/// 非主螢幕以 visiblePosition 為左上角。
Future<void> _coverDisplay(Display display) async {
  final Offset position = display.visiblePosition ?? AppSizes.windowOrigin;
  Size size = display.size;
  if (size.width <= 0 || size.height <= 0) {
    size = AppSizes.fallbackWindowSize;
  }
  await windowManager.setSize(size);
  await windowManager.setPosition(position);
}

/// SPEC-003 FR-05：目標螢幕拔除時退回主螢幕。
Future<void> _onTargetScreenLost() async {
  debugPrint('[main] target display lost, fallback to primary');
  final Display primary = await _detector.resolveTargetDisplay(null);
  await _coverDisplay(primary);
}

class ScreenClockApp extends StatelessWidget {
  const ScreenClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppText.appTitle,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        backgroundColor: AppColors.overlayBackground,
        body: CenterClock(),
      ),
    );
  }
}

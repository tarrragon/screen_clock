import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await _applyOverlayWindowProperties();
  runApp(const ScreenClockApp());
}

/// 依 SPEC-001 序列套用所有遮罩視窗屬性。
///
/// 順序很重要：屬性必須在 `show()` 之前設定完畢，
/// `window_manager` 的部分 setter 在 visible 視窗上行為不一致。
Future<void> _applyOverlayWindowProperties() async {
  await windowManager.waitUntilReadyToShow();
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(AppColors.overlayBackground);
  await windowManager.setHasShadow(AppWindow.hasShadow);
  await windowManager.setAlwaysOnTop(AppWindow.isAlwaysOnTop);
  await windowManager.setIgnoreMouseEvents(AppWindow.ignoreMouseEvents);
  await windowManager.show();
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
        body: SizedBox.expand(),
      ),
    );
  }
}

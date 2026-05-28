import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
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
  await _coverPrimaryScreen();
  await windowManager.show();
}

/// 取得主螢幕尺寸並讓視窗貼合（SPEC-001 FR-01）。
///
/// 偵測失敗時 fallback 到 [AppSizes.fallbackWindowSize]，
/// 避免視窗以 0x0 出現而看不見（SPEC-001 FR-01 替代場景 01a）。
Future<void> _coverPrimaryScreen() async {
  final Size screenSize = await _resolvePrimaryScreenSize();
  await windowManager.setSize(screenSize);
  await windowManager.setPosition(AppSizes.windowOrigin);
}

Future<Size> _resolvePrimaryScreenSize() async {
  try {
    final Display display = await screenRetriever.getPrimaryDisplay();
    final Size size = display.size;
    if (size.width <= 0 || size.height <= 0) {
      return AppSizes.fallbackWindowSize;
    }
    return size;
  } catch (_) {
    return AppSizes.fallbackWindowSize;
  }
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

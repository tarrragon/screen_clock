import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';
import 'models/settings_model.dart';
import 'platform/display_detector.dart';
import 'platform/screen_arg.dart';
import 'services/settings_service.dart';
import 'state/settings_controller.dart';
import 'state/settings_scope.dart';
import 'widgets/center_clock.dart';
import 'widgets/settings_panel.dart';

final DisplayDetector _detector = DisplayDetector();
final SettingsService _settingsService = PreferencesSettingsService();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();
  final SettingsModel settings = await _settingsService.load();
  final SettingsController controller = SettingsController(
    initial: settings,
    service: _settingsService,
  );
  final int displayCount = (await _detector.listDisplays()).length;
  await _applyOverlayWindowProperties(args, settings);
  runApp(
    ScreenClockApp(
      controller: controller,
      availableScreenCount: displayCount,
    ),
  );
}

/// 依 SPEC-001 + SPEC-003 序列套用所有遮罩視窗屬性。
Future<void> _applyOverlayWindowProperties(
  List<String> args,
  SettingsModel settings,
) async {
  await windowManager.waitUntilReadyToShow();
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(AppColors.overlayBackground);
  await windowManager.setHasShadow(AppWindow.hasShadow);
  await windowManager.setAlwaysOnTop(AppWindow.isAlwaysOnTop);
  await windowManager.setIgnoreMouseEvents(AppWindow.ignoreMouseEvents);

  final int targetIndex = parseScreenArg(args) ?? settings.targetScreenIndex;
  final Display target = await _detector.resolveTargetDisplay(targetIndex);
  await _coverDisplay(target);
  await windowManager.show();

  _detector.startWatching(
    watchedIndex: targetIndex,
    onTargetLost: _onTargetScreenLost,
  );
}

Future<void> _coverDisplay(Display display) async {
  final Offset position = display.visiblePosition ?? AppSizes.windowOrigin;
  Size size = display.size;
  if (size.width <= 0 || size.height <= 0) {
    size = AppSizes.fallbackWindowSize;
  }
  await windowManager.setSize(size);
  await windowManager.setPosition(position);
}

Future<void> _onTargetScreenLost() async {
  debugPrint('[main] target display lost, fallback to primary');
  final Display primary = await _detector.resolveTargetDisplay(null);
  await _coverDisplay(primary);
}

class ScreenClockApp extends StatefulWidget {
  const ScreenClockApp({
    super.key,
    required this.controller,
    required this.availableScreenCount,
  });

  final SettingsController controller;
  final int availableScreenCount;

  @override
  State<ScreenClockApp> createState() => _ScreenClockAppState();
}

class _ScreenClockAppState extends State<ScreenClockApp> {
  bool _panelOpen = false;
  HotKey? _registeredHotKey;

  @override
  void initState() {
    super.initState();
    _registerHotKey();
  }

  @override
  void dispose() {
    final HotKey? key = _registeredHotKey;
    if (key != null) {
      hotKeyManager.unregister(key);
    }
    _registeredHotKey = null;
    super.dispose();
  }

  Future<void> _registerHotKey() async {
    final HotKey hotKey = HotKey(
      key: PhysicalKeyboardKey.comma,
      modifiers: <HotKeyModifier>[
        HotKeyModifier.meta,
        HotKeyModifier.alt,
      ],
      scope: HotKeyScope.system,
    );
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _togglePanel(),
      );
      _registeredHotKey = hotKey;
    } catch (error, stack) {
      debugPrint('[main] hotkey register failed: $error');
      debugPrint(stack.toString());
    }
  }

  Future<void> _togglePanel() async {
    if (_panelOpen) {
      // 由 panel 內 Save / Cancel 觸發；此分支保留給日後可能的程式化 toggle。
      return;
    }
    setState(() => _panelOpen = true);
    try {
      await windowManager.setIgnoreMouseEvents(false);
    } catch (error) {
      debugPrint('[main] disable click-through failed: $error');
    }
  }

  Future<void> _onPanelClosed() async {
    setState(() => _panelOpen = false);
    try {
      await windowManager
          .setIgnoreMouseEvents(AppWindow.ignoreMouseEvents);
    } catch (error) {
      debugPrint('[main] restore click-through failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: widget.controller,
      child: MaterialApp(
        title: AppText.appTitle,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.overlayBackground,
          body: Stack(
            children: <Widget>[
              const CenterClock(),
              if (_panelOpen)
                _PanelHost(
                  availableScreenCount: widget.availableScreenCount,
                  onClosed: _onPanelClosed,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 包覆 [SettingsPanel]，攔截 Navigator 的 pop 行為以恢復 click-through。
class _PanelHost extends StatelessWidget {
  const _PanelHost({
    required this.availableScreenCount,
    required this.onClosed,
  });

  final int availableScreenCount;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) onClosed();
      },
      child: _DismissibleOverlay(
        onDismiss: onClosed,
        child: SettingsPanel(availableScreenCount: availableScreenCount),
      ),
    );
  }
}

/// 暗背景遮罩 + Esc 鍵 / 外部點擊關閉。
class _DismissibleOverlay extends StatelessWidget {
  const _DismissibleOverlay({required this.onDismiss, required this.child});

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: Container(color: const Color(0x80000000)),
          ),
        ),
        Center(child: child),
      ],
    );
  }
}

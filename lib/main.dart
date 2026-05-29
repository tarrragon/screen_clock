import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';
import 'models/settings_model.dart';
import 'platform/display_detector.dart';
import 'platform/screen_arg.dart';
import 'services/auto_launch_service.dart';
import 'services/settings_service.dart';
import 'state/settings_controller.dart';
import 'state/settings_scope.dart';
import 'widgets/center_clock.dart';
import 'widgets/settings_panel.dart';

final DisplayDetector _detector = DisplayDetector();
final SettingsService _settingsService = PreferencesSettingsService();
final AutoLaunchService _autoLaunchService = LaunchAtStartupAutoLaunchService();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();
  SettingsModel settings = await _settingsService.load();
  // SPEC-006 FR-02：OS 開機啟動狀態為準，覆寫 saved settings。
  final bool osAutoLaunch = await _autoLaunchService.isEnabled();
  if (osAutoLaunch != settings.autoLaunch) {
    settings = settings.copyWith(autoLaunch: osAutoLaunch);
    await _settingsService.save(settings);
  }
  final SettingsController controller = SettingsController(
    initial: settings,
    service: _settingsService,
    autoLaunchService: _autoLaunchService,
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
  // 顯示於所有一般桌面（Spaces），切換桌面時遮罩時鐘跟隨；
  // visibleOnFullScreen=false → 不侵入全螢幕 app 的獨立 Space。
  await windowManager.setVisibleOnAllWorkspaces(
    AppWindow.visibleOnAllWorkspaces,
    visibleOnFullScreen: AppWindow.visibleOnFullScreen,
  );

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

class _ScreenClockAppState extends State<ScreenClockApp> with TrayListener {
  bool _panelOpen = false;
  bool _clockVisible = true;
  HotKey? _registeredHotKey;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _registerHotKey();
    _initTray();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    final HotKey? key = _registeredHotKey;
    if (key != null) {
      hotKeyManager.unregister(key);
    }
    _registeredHotKey = null;
    super.dispose();
  }

  /// 初始化狀態列（選單列）項目：透明 icon + 文字 + 選單。
  Future<void> _initTray() async {
    try {
      // macOS 需先 setIcon 才會建立 status item（見 tray_manager 實作）。
      await trayManager.setIcon(AppText.trayIconAsset);
      await trayManager.setTitle(AppText.trayTitle);
      await trayManager.setContextMenu(_buildTrayMenu());
    } catch (error, stack) {
      debugPrint('[main] tray init failed: $error');
      debugPrint(stack.toString());
    }
  }

  /// 依目前時鐘顯示狀態建立選單（顯示/隱藏標籤動態切換）。
  Menu _buildTrayMenu() {
    return Menu(
      items: <MenuItem>[
        MenuItem(key: 'settings', label: AppText.trayMenuSettings),
        MenuItem(
          key: 'toggle_visibility',
          label: _clockVisible
              ? AppText.trayMenuHideClock
              : AppText.trayMenuShowClock,
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: AppText.trayMenuQuit),
      ],
    );
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'settings':
        _openSettingsFromTray();
      case 'toggle_visibility':
        _toggleClockVisibility();
      case 'quit':
        _quit();
    }
  }

  /// 狀態列「設定…」：取得焦點後開啟面板（agent app 需主動 focus）。
  Future<void> _openSettingsFromTray() async {
    try {
      await windowManager.focus();
    } catch (error) {
      debugPrint('[main] focus before settings failed: $error');
    }
    await _togglePanel();
  }

  /// 切換時鐘「內容」顯示 / 隱藏，並更新選單標籤。
  ///
  /// 不動原生視窗（避免對 always-on-top + 全 Spaces 透明視窗呼叫 hide/show
  /// 造成崩潰）；視窗本就透明 + click-through，不畫時鐘內容即視覺隱藏。
  Future<void> _toggleClockVisibility() async {
    setState(() => _clockVisible = !_clockVisible);
    await trayManager.setContextMenu(_buildTrayMenu());
  }

  /// 狀態列「離開」：銷毀視窗 → 觸發 app 終止。
  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.destroy();
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
              if (_clockVisible) const CenterClock(),
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
        child: SettingsPanel(
          availableScreenCount: availableScreenCount,
          onClose: onClosed,
        ),
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

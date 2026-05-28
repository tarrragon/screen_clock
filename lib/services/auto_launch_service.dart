import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../app_constants.dart';

/// 開機自動啟動服務（SPEC-006 FR-01 + FR-02）。
abstract class AutoLaunchService {
  Future<bool> isEnabled();

  /// 變更狀態；回傳實際生效結果（可能因權限失敗）。
  Future<bool> setEnabled(bool enabled);
}

/// 預設實作：包裝 [launch_at_startup] 套件。
///
/// MVP 階段只實際處理 macOS；其他平台維持 noop（套件本身已負責）。
class LaunchAtStartupAutoLaunchService implements AutoLaunchService {
  LaunchAtStartupAutoLaunchService();

  bool _setupDone = false;

  void _ensureSetup() {
    if (_setupDone) return;
    launchAtStartup.setup(
      appName: AppText.appTitle,
      appPath: Platform.resolvedExecutable,
    );
    _setupDone = true;
  }

  @override
  Future<bool> isEnabled() async {
    _ensureSetup();
    try {
      return await launchAtStartup.isEnabled();
    } catch (error, stack) {
      debugPrint('[AutoLaunchService] isEnabled failed: $error');
      debugPrint(stack.toString());
      return false;
    }
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    _ensureSetup();
    try {
      if (enabled) {
        return await launchAtStartup.enable();
      } else {
        return await launchAtStartup.disable();
      }
    } catch (error, stack) {
      debugPrint(
        '[AutoLaunchService] setEnabled($enabled) failed: $error',
      );
      debugPrint(stack.toString());
      return false;
    }
  }
}

/// 測試替身：記憶體狀態。
class InMemoryAutoLaunchService implements AutoLaunchService {
  InMemoryAutoLaunchService({bool initial = false}) : _enabled = initial;

  bool _enabled;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<bool> setEnabled(bool enabled) async {
    _enabled = enabled;
    return true;
  }
}

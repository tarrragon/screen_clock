import 'package:flutter/material.dart';

import '../models/settings_model.dart';
import 'settings_controller.dart';

/// Widget tree 中提供 [SettingsController] 的 InheritedNotifier。
///
/// 子 widget 透過 [SettingsScope.of] 取得 [SettingsModel]，當 model 變化時
/// 自動 rebuild（SPEC-005 FR-04 即時預覽機制）。
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 取得當前 settings；不存在時拋例外（呼叫者必須在 SettingsScope 子樹下）。
  static SettingsModel of(BuildContext context) {
    final SettingsScope? scope =
        context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope.of called outside the scope');
    return scope!.notifier!.value;
  }

  /// 取得 controller（用於寫入 / persist）。
  static SettingsController controllerOf(BuildContext context) {
    final SettingsScope? scope =
        context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope.controllerOf called outside the scope');
    return scope!.notifier!;
  }
}

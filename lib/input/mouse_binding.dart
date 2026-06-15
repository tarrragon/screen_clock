import 'package:flutter/foundation.dart';

import '../app_constants.dart';
import 'mouse_action.dart';

/// 一筆滑鼠按鍵綁定（SPEC-007 FR-01）。
///
/// 將實體滑鼠按鍵（[buttonNumber]）綁定到一個 [MouseAction]；不可變，
/// 變更透過 [copyWith]。序列化往返由 [toJson] / [MouseBinding.fromJson]
/// 負責，單筆型別錯誤時 fromJson 回傳 null，呼叫端略過該筆不拋例外。
@immutable
class MouseBinding {
  const MouseBinding({
    required this.buttonNumber,
    required this.action,
  });

  /// 容錯還原：buttonNumber 缺欄 / 型別錯誤，或 action 無法解析 → 回傳 null。
  static MouseBinding? fromJson(Map<String, dynamic> json) {
    final Object? button = json[AppInputBinding.buttonNumberKey];
    if (button is! int) return null;
    final Object? rawAction = json[AppInputBinding.actionKey];
    if (rawAction is! Map<String, dynamic>) return null;
    final MouseAction? action = MouseAction.fromJson(rawAction);
    if (action == null) return null;
    return MouseBinding(buttonNumber: button, action: action);
  }

  final int buttonNumber;
  final MouseAction action;

  Map<String, Object> toJson() {
    return <String, Object>{
      AppInputBinding.buttonNumberKey: buttonNumber,
      AppInputBinding.actionKey: action.toJson(),
    };
  }

  MouseBinding copyWith({
    int? buttonNumber,
    MouseAction? action,
  }) {
    return MouseBinding(
      buttonNumber: buttonNumber ?? this.buttonNumber,
      action: action ?? this.action,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MouseBinding &&
        other.buttonNumber == buttonNumber &&
        other.action == action;
  }

  @override
  int get hashCode => Object.hash(buttonNumber, action);
}

/// 對綁定清單依 [MouseBinding.buttonNumber] 去重（SPEC-007 FR-01）。
///
/// 規則：同一 buttonNumber 後者覆蓋前者，輸出保留各 buttonNumber 末次出現的
/// 綁定，並維持末次出現的順序。此規則固定，序列化往返與面板層皆依此收斂。
List<MouseBinding> dedupeBindingsByButton(List<MouseBinding> bindings) {
  final Map<int, MouseBinding> byButton = <int, MouseBinding>{};
  for (final MouseBinding binding in bindings) {
    byButton[binding.buttonNumber] = binding;
  }
  return List<MouseBinding>.unmodifiable(byButton.values);
}

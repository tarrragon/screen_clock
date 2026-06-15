import 'package:flutter/foundation.dart';

import '../app_constants.dart';

/// 拖曳滾動方向（SPEC-007 FR-01）。
///
/// [natural]：往下拖 → 往下捲；[inverted]：相反。
enum ScrollDirection { natural, inverted }

/// 滑鼠動作型別標籤（SPEC-007 FR-01）。
///
/// 對應序列化的 type 欄；新增動作型別時於此擴充。
enum MouseActionType { dragScroll, hotkey }

/// 一個滑鼠按鍵綁定的動作（SPEC-007 FR-01）。
///
/// 可擴充型別（DragScroll / Hotkey），以 [type] 區分；不可變，
/// 透過 [toJson] 序列化、[MouseAction.fromJson] 依 type 分派還原。
@immutable
sealed class MouseAction {
  const MouseAction();

  /// 依 type 欄分派還原；未知 / 缺欄 type 回傳 null（容錯，呼叫端略過該筆）。
  static MouseAction? fromJson(Map<String, dynamic> json) {
    final Object? type = json[AppInputBinding.actionTypeKey];
    if (type == AppInputBinding.dragScrollType) {
      return DragScrollAction.fromJson(json);
    }
    if (type == AppInputBinding.hotkeyType) {
      return HotkeyAction.fromJson(json);
    }
    return null;
  }

  MouseActionType get type;

  Map<String, Object> toJson();
}

/// 拖曳滾動動作（SPEC-007 FR-01）。
@immutable
class DragScrollAction extends MouseAction {
  const DragScrollAction({
    this.direction = ScrollDirection.natural,
    this.sensitivity = AppInputBinding.defaultDragScrollSensitivity,
  });

  /// 容錯還原：方向 / 靈敏度缺欄或型別錯誤 → 補預設。
  factory DragScrollAction.fromJson(Map<String, dynamic> json) {
    return DragScrollAction(
      direction: _asScrollDirection(json[AppInputBinding.directionKey]) ??
          ScrollDirection.natural,
      sensitivity: _asDouble(json[AppInputBinding.sensitivityKey]) ??
          AppInputBinding.defaultDragScrollSensitivity,
    );
  }

  final ScrollDirection direction;
  final double sensitivity;

  @override
  MouseActionType get type => MouseActionType.dragScroll;

  @override
  Map<String, Object> toJson() {
    return <String, Object>{
      AppInputBinding.actionTypeKey: AppInputBinding.dragScrollType,
      AppInputBinding.directionKey: direction.name,
      AppInputBinding.sensitivityKey: sensitivity,
    };
  }

  DragScrollAction copyWith({
    ScrollDirection? direction,
    double? sensitivity,
  }) {
    return DragScrollAction(
      direction: direction ?? this.direction,
      sensitivity: sensitivity ?? this.sensitivity,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DragScrollAction &&
        other.direction == direction &&
        other.sensitivity == sensitivity;
  }

  @override
  int get hashCode => Object.hash(direction, sensitivity);
}

/// 快捷鍵動作（SPEC-007 FR-01）。
///
/// 以實體鍵碼 + 修飾鍵集合表達組合（如 Cmd+Shift+4）。
@immutable
class HotkeyAction extends MouseAction {
  HotkeyAction({
    required this.keyCode,
    List<int> modifiers = const <int>[],
  }) : modifiers = List<int>.unmodifiable(modifiers);

  /// 容錯還原：keyCode 缺欄 / 型別錯誤 → 0；modifiers 非 int 清單 → 空清單。
  factory HotkeyAction.fromJson(Map<String, dynamic> json) {
    return HotkeyAction(
      keyCode: _asInt(json[AppInputBinding.keyCodeKey]) ?? 0,
      modifiers: _asIntList(json[AppInputBinding.modifiersKey]),
    );
  }

  final int keyCode;

  /// 修飾鍵集合（穩定排序的 int 清單，可序列化）。
  final List<int> modifiers;

  @override
  MouseActionType get type => MouseActionType.hotkey;

  @override
  Map<String, Object> toJson() {
    return <String, Object>{
      AppInputBinding.actionTypeKey: AppInputBinding.hotkeyType,
      AppInputBinding.keyCodeKey: keyCode,
      AppInputBinding.modifiersKey: List<int>.from(modifiers),
    };
  }

  HotkeyAction copyWith({
    int? keyCode,
    List<int>? modifiers,
  }) {
    return HotkeyAction(
      keyCode: keyCode ?? this.keyCode,
      modifiers: modifiers ?? this.modifiers,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HotkeyAction &&
        other.keyCode == keyCode &&
        listEquals(other.modifiers, modifiers);
  }

  @override
  int get hashCode => Object.hash(keyCode, Object.hashAll(modifiers));
}

ScrollDirection? _asScrollDirection(Object? value) {
  if (value is! String) return null;
  for (final ScrollDirection direction in ScrollDirection.values) {
    if (direction.name == value) return direction;
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 將任意值解析為 int 清單；非清單 / 含非 int 元素 → 過濾掉壞元素。
List<int> _asIntList(Object? value) {
  if (value is! List) return const <int>[];
  final List<int> result = <int>[];
  for (final Object? element in value) {
    final int? parsed = _asInt(element);
    if (parsed != null) result.add(parsed);
  }
  return result;
}

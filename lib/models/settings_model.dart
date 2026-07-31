import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../input/mouse_action.dart';
import '../input/mouse_binding.dart';

/// 使用者設定資料模型（SPEC-004 FR-01）。
///
/// schema v4（SPEC-009 A.1）；除 [birthDate] 外所有欄位 non-null、不可變；
/// 變更透過 [copyWith]。
@immutable
class SettingsModel {
  const SettingsModel({
    required this.fontSize,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
    required this.timeFormat,
    required this.targetScreenIndex,
    required this.autoLaunch,
    this.birthDate,
    this.lifeTimerMode = false,
    this.bindings = const <MouseBinding>[],
    this.bindingsSeeded = false,
    this.cursorLocatorEnabled = true,
    this.cursorLocatorEffectDurationSeconds = 1.5,
    // 系統藍（Material primary blue 的 ARGB 值，避免 MaterialColor 型別
    // 導致 round-trip 後 == 因 runtimeType 不同而失效）。常數登錄延後由
    // 1.4.0-W1-001.1（本票依約束不得觸碰 app_constants.dart）補上。
    this.cursorLocatorPrimaryColor = const Color(0xFF2196F3), // color-exempt
  });

  /// 重現 v0.x 寫死預設值（SPEC-004 FR-01）。
  ///
  /// bindings 預設含一筆側鍵拖曳滾動（SPEC-007 FR-03），讓功能首次啟動即可用：
  /// 按住 button 4 上下拖曳 → 捲動游標下方視窗（natural 方向、預設靈敏度）。
  factory SettingsModel.defaults() {
    return const SettingsModel(
      fontSize: AppSizes.clockFontSize,
      fillColor: AppColors.clockFill,
      strokeColor: AppColors.clockStroke,
      strokeWidth: AppSizes.clockStrokeWidth,
      timeFormat: AppText.timeFormat,
      targetScreenIndex: 0,
      autoLaunch: false,
      birthDate: null,
      lifeTimerMode: false,
      bindings: <MouseBinding>[
        MouseBinding(
          buttonNumber: AppInputBinding.defaultDragScrollButton,
          action: DragScrollAction(),
        ),
      ],
      bindingsSeeded: true,
      cursorLocatorEnabled: true,
      cursorLocatorEffectDurationSeconds: 1.5,
      cursorLocatorPrimaryColor: Color(0xFF2196F3), // color-exempt: 見建構子註解
    );
  }

  /// 容錯解析（SPEC-004 FR-02）。
  ///
  /// 缺欄位 / 型別錯誤 → 對應 default 該欄；整體解析永不拋例外。
  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    final SettingsModel d = SettingsModel.defaults();
    return SettingsModel(
      fontSize: _asDouble(json['fontSize']) ?? d.fontSize,
      fillColor: _asColor(json['fillColor']) ?? d.fillColor,
      strokeColor: _asColor(json['strokeColor']) ?? d.strokeColor,
      strokeWidth: _asDouble(json['strokeWidth']) ?? d.strokeWidth,
      timeFormat: _asString(json['timeFormat']) ?? d.timeFormat,
      targetScreenIndex:
          _asInt(json['targetScreenIndex']) ?? d.targetScreenIndex,
      autoLaunch: _asBool(json['autoLaunch']) ?? d.autoLaunch,
      birthDate: _asDateTime(json['birthDate']) ?? d.birthDate,
      lifeTimerMode: _asBool(json['lifeTimerMode']) ?? d.lifeTimerMode,
      bindings: _bindingsFromJson(json[AppSettingsKeys.bindingsKey]),
      bindingsSeeded:
          _asBool(json[AppSettingsKeys.bindingsSeededKey]) ?? false,
      cursorLocatorEnabled:
          _asBool(json['cursorLocatorEnabled']) ?? d.cursorLocatorEnabled,
      cursorLocatorEffectDurationSeconds:
          _asDouble(json['cursorLocatorEffectDurationSeconds']) ??
              d.cursorLocatorEffectDurationSeconds,
      cursorLocatorPrimaryColor:
          _asColor(json['cursorLocatorPrimaryColor']) ??
              d.cursorLocatorPrimaryColor,
    );
  }

  /// schemaVersion 4：新增游標定位器三項設定（SPEC-008 FR-06）。
  /// v3 及更早資料缺這三欄，fromJson 解析為對應預設值，向後相容（INV-03）。
  static const int schemaVersion = 4;

  final double fontSize;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final String timeFormat;
  final int targetScreenIndex;
  final bool autoLaunch;

  /// 出生日期（生命計時模式用）；未設定為 null。
  final DateTime? birthDate;

  /// 是否啟用生命計時模式（顯示即時年齡取代時間）。
  final bool lifeTimerMode;

  /// 滑鼠按鍵綁定清單（SPEC-007 FR-02）；同 buttonNumber 已去重。
  final List<MouseBinding> bindings;

  /// 一次性預設綁定 seed migration 旗標（W3-002）。
  ///
  /// false 代表舊資料尚未遷移；load 時若為 false 會評估補入預設綁定並標記為 true。
  final bool bindingsSeeded;

  /// 游標定位器啟用開關（SPEC-008 FR-06）。
  final bool cursorLocatorEnabled;

  /// 游標定位器特效時長，單位秒（SPEC-008 FR-06）；值域 0.5–3.0。
  final double cursorLocatorEffectDurationSeconds;

  /// 游標定位器主色調（SPEC-008 FR-06）；以 ARGB int 經 [_asColor] 存取。
  final Color cursorLocatorPrimaryColor;

  Map<String, Object> toJson() {
    final Map<String, Object> json = <String, Object>{
      'schemaVersion': schemaVersion,
      'fontSize': fontSize,
      'fillColor': _colorToInt(fillColor),
      'strokeColor': _colorToInt(strokeColor),
      'strokeWidth': strokeWidth,
      'timeFormat': timeFormat,
      'targetScreenIndex': targetScreenIndex,
      'autoLaunch': autoLaunch,
      'lifeTimerMode': lifeTimerMode,
    };
    // birthDate 以 epoch 毫秒儲存；未設定時不寫入（Map 不存 null）。
    final DateTime? birth = birthDate;
    if (birth != null) {
      json['birthDate'] = birth.millisecondsSinceEpoch;
    }
    json[AppSettingsKeys.bindingsKey] = <Map<String, Object>>[
      for (final MouseBinding binding in bindings) binding.toJson(),
    ];
    json[AppSettingsKeys.bindingsSeededKey] = bindingsSeeded;
    json['cursorLocatorEnabled'] = cursorLocatorEnabled;
    json['cursorLocatorEffectDurationSeconds'] =
        cursorLocatorEffectDurationSeconds;
    json['cursorLocatorPrimaryColor'] = _colorToInt(cursorLocatorPrimaryColor);
    return json;
  }

  SettingsModel copyWith({
    double? fontSize,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    String? timeFormat,
    int? targetScreenIndex,
    bool? autoLaunch,
    DateTime? birthDate,
    bool? lifeTimerMode,
    List<MouseBinding>? bindings,
    bool? bindingsSeeded,
    bool? cursorLocatorEnabled,
    double? cursorLocatorEffectDurationSeconds,
    Color? cursorLocatorPrimaryColor,
  }) {
    return SettingsModel(
      fontSize: fontSize ?? this.fontSize,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      timeFormat: timeFormat ?? this.timeFormat,
      targetScreenIndex: targetScreenIndex ?? this.targetScreenIndex,
      autoLaunch: autoLaunch ?? this.autoLaunch,
      birthDate: birthDate ?? this.birthDate,
      lifeTimerMode: lifeTimerMode ?? this.lifeTimerMode,
      bindings: bindings != null
          ? dedupeBindingsByButton(bindings)
          : this.bindings,
      bindingsSeeded: bindingsSeeded ?? this.bindingsSeeded,
      cursorLocatorEnabled: cursorLocatorEnabled ?? this.cursorLocatorEnabled,
      cursorLocatorEffectDurationSeconds:
          cursorLocatorEffectDurationSeconds ??
              this.cursorLocatorEffectDurationSeconds,
      cursorLocatorPrimaryColor:
          cursorLocatorPrimaryColor ?? this.cursorLocatorPrimaryColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsModel &&
        other.fontSize == fontSize &&
        other.fillColor == fillColor &&
        other.strokeColor == strokeColor &&
        other.strokeWidth == strokeWidth &&
        other.timeFormat == timeFormat &&
        other.targetScreenIndex == targetScreenIndex &&
        other.autoLaunch == autoLaunch &&
        other.birthDate == birthDate &&
        other.lifeTimerMode == lifeTimerMode &&
        listEquals(other.bindings, bindings) &&
        other.bindingsSeeded == bindingsSeeded &&
        other.cursorLocatorEnabled == cursorLocatorEnabled &&
        other.cursorLocatorEffectDurationSeconds ==
            cursorLocatorEffectDurationSeconds &&
        other.cursorLocatorPrimaryColor == cursorLocatorPrimaryColor;
  }

  @override
  int get hashCode => Object.hash(
        fontSize,
        fillColor,
        strokeColor,
        strokeWidth,
        timeFormat,
        targetScreenIndex,
        autoLaunch,
        birthDate,
        lifeTimerMode,
        Object.hashAll(bindings),
        bindingsSeeded,
        cursorLocatorEnabled,
        cursorLocatorEffectDurationSeconds,
        cursorLocatorPrimaryColor,
      );
}

/// 容錯解析 bindings 欄（SPEC-007 FR-02）。
///
/// 非清單 → 空清單；單筆型別錯誤 / 未知 action type → 略過該筆，不拋例外；
/// 同 buttonNumber 依 [dedupeBindingsByButton] 規則收斂。
List<MouseBinding> _bindingsFromJson(Object? value) {
  if (value is! List) return const <MouseBinding>[];
  final List<MouseBinding> parsed = <MouseBinding>[];
  for (final Object? element in value) {
    if (element is! Map<String, dynamic>) continue;
    final MouseBinding? binding = MouseBinding.fromJson(element);
    if (binding != null) parsed.add(binding);
  }
  return dedupeBindingsByButton(parsed);
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

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return null;
}

String? _asString(Object? value) => value is String ? value : null;

/// 解析 epoch 毫秒（int）為 [DateTime]；型別不符或缺值回傳 null。
DateTime? _asDateTime(Object? value) {
  final int? millis = _asInt(value);
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

Color? _asColor(Object? value) {
  final int? argb = _asInt(value);
  if (argb == null) return null;
  return Color(argb);
}

/// 對應 [Color] 在 shared_preferences 中以 ARGB32 int 儲存（SPEC-004 設計約束）。
int _colorToInt(Color color) {
  final int a = (color.a * 255).round() & 0xff;
  final int r = (color.r * 255).round() & 0xff;
  final int g = (color.g * 255).round() & 0xff;
  final int b = (color.b * 255).round() & 0xff;
  return (a << 24) | (r << 16) | (g << 8) | b;
}

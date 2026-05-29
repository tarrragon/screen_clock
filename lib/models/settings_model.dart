import 'package:flutter/material.dart';

import '../app_constants.dart';

/// 使用者設定資料模型（SPEC-004 FR-01）。
///
/// MVP 階段 7 個欄位 + schemaVersion。所有欄位 non-null、不可變；
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
  });

  /// 重現 v0.x 寫死預設值（SPEC-004 FR-01）。
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
    );
  }

  /// schemaVersion 2：新增 birthDate / lifeTimerMode（生命計時模式）。
  /// 舊版（v1）資料缺這兩欄，fromJson 以 default 補齊，向後相容。
  static const int schemaVersion = 2;

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
        other.lifeTimerMode == lifeTimerMode;
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
      );
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

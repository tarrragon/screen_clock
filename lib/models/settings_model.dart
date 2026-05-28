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
    );
  }

  static const int schemaVersion = 1;

  final double fontSize;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final String timeFormat;
  final int targetScreenIndex;
  final bool autoLaunch;

  Map<String, Object> toJson() {
    return <String, Object>{
      'schemaVersion': schemaVersion,
      'fontSize': fontSize,
      'fillColor': _colorToInt(fillColor),
      'strokeColor': _colorToInt(strokeColor),
      'strokeWidth': strokeWidth,
      'timeFormat': timeFormat,
      'targetScreenIndex': targetScreenIndex,
      'autoLaunch': autoLaunch,
    };
  }

  SettingsModel copyWith({
    double? fontSize,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    String? timeFormat,
    int? targetScreenIndex,
    bool? autoLaunch,
  }) {
    return SettingsModel(
      fontSize: fontSize ?? this.fontSize,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      timeFormat: timeFormat ?? this.timeFormat,
      targetScreenIndex: targetScreenIndex ?? this.targetScreenIndex,
      autoLaunch: autoLaunch ?? this.autoLaunch,
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
        other.autoLaunch == autoLaunch;
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

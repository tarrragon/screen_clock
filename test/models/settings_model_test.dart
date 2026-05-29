import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/models/settings_model.dart';

void main() {
  group('SettingsModel.defaults', () {
    test('matches the v0.x hardcoded constants', () {
      final SettingsModel d = SettingsModel.defaults();
      expect(d.fontSize, AppSizes.clockFontSize);
      expect(d.fillColor, AppColors.clockFill);
      expect(d.strokeColor, AppColors.clockStroke);
      expect(d.strokeWidth, AppSizes.clockStrokeWidth);
      expect(d.timeFormat, AppText.timeFormat);
      expect(d.targetScreenIndex, 0);
      expect(d.autoLaunch, false);
    });
  });

  group('SettingsModel.copyWith', () {
    test('does not mutate the original', () {
      final SettingsModel original = SettingsModel.defaults();
      final SettingsModel updated = original.copyWith(fontSize: 80);
      expect(updated.fontSize, 80);
      expect(original.fontSize, AppSizes.clockFontSize);
    });

    test('preserves other fields when one changes', () {
      final SettingsModel original = SettingsModel.defaults();
      final SettingsModel updated = original.copyWith(autoLaunch: true);
      expect(updated.autoLaunch, true);
      expect(updated.timeFormat, original.timeFormat);
      expect(updated.fillColor, original.fillColor);
    });
  });

  group('SettingsModel round-trip', () {
    test('fromJson(toJson(model)) == model', () {
      final SettingsModel original = SettingsModel.defaults().copyWith(
        fontSize: 90,
        fillColor: const Color(0xFFAABBCC),
        strokeColor: const Color(0xFF112233),
        timeFormat: 'HH:mm',
        targetScreenIndex: 2,
        autoLaunch: true,
      );
      final SettingsModel decoded =
          SettingsModel.fromJson(original.toJson());
      expect(decoded, original);
    });

    test('round-trips birthDate 與 lifeTimerMode', () {
      final SettingsModel original = SettingsModel.defaults().copyWith(
        birthDate: DateTime.fromMillisecondsSinceEpoch(946684800000),
        lifeTimerMode: true,
      );
      final SettingsModel decoded =
          SettingsModel.fromJson(original.toJson());
      expect(decoded, original);
      expect(decoded.lifeTimerMode, true);
      expect(decoded.birthDate,
          DateTime.fromMillisecondsSinceEpoch(946684800000));
    });

    test('birthDate 未設定時 toJson 不含該鍵', () {
      final Map<String, Object> json = SettingsModel.defaults().toJson();
      expect(json.containsKey('birthDate'), isFalse);
    });

    test('fromJson empty map yields defaults', () {
      expect(SettingsModel.fromJson(const <String, Object?>{}),
          SettingsModel.defaults());
    });

    test('fromJson tolerates invalid types', () {
      final Map<String, Object?> garbage = <String, Object?>{
        'fontSize': 'not a number',
        'fillColor': 'not an int',
        'targetScreenIndex': 'NaN',
        'autoLaunch': 'maybe',
        'timeFormat': 42,
      };
      final SettingsModel decoded = SettingsModel.fromJson(garbage);
      expect(decoded, SettingsModel.defaults());
    });
  });

  test('equality and hashCode reflect value semantics', () {
    final SettingsModel a = SettingsModel.defaults();
    final SettingsModel b = SettingsModel.defaults();
    final SettingsModel c = a.copyWith(autoLaunch: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
  });
}

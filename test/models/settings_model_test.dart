import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/input/mouse_action.dart';
import 'package:screen_clock/input/mouse_binding.dart';
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

    test('fromJson empty map yields defaults (no bindings key → empty list)',
        () {
      // 空 JSON 缺 bindings 鍵，依向後相容解析為空清單（見 v2 相容測試）；
      // 其餘純量欄位回退 defaults。故與 defaults().copyWith(空綁定) 相等。
      expect(
        SettingsModel.fromJson(const <String, Object?>{}),
        SettingsModel.defaults().copyWith(bindings: const <MouseBinding>[]),
      );
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
      expect(
        decoded,
        SettingsModel.defaults().copyWith(bindings: const <MouseBinding>[]),
      );
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

  group('SettingsModel bindings (schema v3, SPEC-007 FR-02)', () {
    test('schemaVersion is 3', () {
      expect(SettingsModel.schemaVersion, 3);
    });

    test('defaults to a single side-button drag-scroll binding', () {
      final List<MouseBinding> bindings = SettingsModel.defaults().bindings;
      expect(bindings, hasLength(1));
      final MouseBinding binding = bindings.single;
      expect(binding.buttonNumber, AppInputBinding.defaultDragScrollButton);
      expect(binding.action, isA<DragScrollAction>());
      final DragScrollAction action = binding.action as DragScrollAction;
      expect(action.direction, ScrollDirection.natural);
      expect(
        action.sensitivity,
        AppInputBinding.defaultDragScrollSensitivity,
      );
    });

    test('round-trips bindings (drag scroll + hotkey)', () {
      final SettingsModel original = SettingsModel.defaults().copyWith(
        bindings: <MouseBinding>[
          const MouseBinding(
            buttonNumber: 3,
            action: DragScrollAction(direction: ScrollDirection.inverted),
          ),
          MouseBinding(
            buttonNumber: 4,
            action: HotkeyAction(keyCode: 21, modifiers: <int>[55, 56]),
          ),
        ],
      );
      final SettingsModel decoded = SettingsModel.fromJson(original.toJson());
      expect(decoded, original);
      expect(decoded.bindings.length, 2);
    });

    test('v2 data without bindings is parsed as empty list (backward compat)',
        () {
      final Map<String, Object> v2Json = SettingsModel.defaults().toJson()
        ..remove(AppSettingsKeys.bindingsKey)
        ..['schemaVersion'] = 2;
      expect(v2Json.containsKey(AppSettingsKeys.bindingsKey), isFalse);
      final SettingsModel decoded = SettingsModel.fromJson(v2Json);
      expect(decoded.bindings, isEmpty);
    });

    test('skips a single corrupt binding without dropping the others', () {
      final Map<String, Object> json = SettingsModel.defaults().toJson();
      json[AppSettingsKeys.bindingsKey] = <Object>[
        const MouseBinding(buttonNumber: 3, action: DragScrollAction())
            .toJson(),
        <String, dynamic>{
          AppInputBinding.buttonNumberKey: 4,
          AppInputBinding.actionKey: <String, dynamic>{
            AppInputBinding.actionTypeKey: 'corruptType',
          },
        },
      ];
      final SettingsModel decoded = SettingsModel.fromJson(json);
      expect(decoded.bindings.length, 1);
      expect(decoded.bindings.single.buttonNumber, 3);
    });

    test('dedupes same buttonNumber on construction', () {
      final SettingsModel model = SettingsModel.defaults().copyWith(
        bindings: <MouseBinding>[
          const MouseBinding(buttonNumber: 3, action: DragScrollAction()),
          MouseBinding(buttonNumber: 3, action: HotkeyAction(keyCode: 9)),
        ],
      );
      expect(model.bindings.length, 1);
      expect(model.bindings.single.action, isA<HotkeyAction>());
    });

    test('copyWith with bindings does not mutate the original', () {
      final SettingsModel original = SettingsModel.defaults().copyWith(
        bindings: const <MouseBinding>[],
      );
      final SettingsModel updated = original.copyWith(
        bindings: <MouseBinding>[
          const MouseBinding(buttonNumber: 3, action: DragScrollAction()),
        ],
      );
      expect(updated.bindings.length, 1);
      expect(original.bindings, isEmpty);
    });
  });
}

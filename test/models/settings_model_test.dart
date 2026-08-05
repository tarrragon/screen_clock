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
      // 缺 bindingsSeeded 鍵代表未遷移舊資料 → false（W3-002 seed migration）；
      // 其餘純量欄位回退 defaults。
      expect(
        SettingsModel.fromJson(const <String, Object?>{}),
        SettingsModel.defaults().copyWith(
          bindings: const <MouseBinding>[],
          bindingsSeeded: false,
        ),
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
        SettingsModel.defaults().copyWith(
          bindings: const <MouseBinding>[],
          bindingsSeeded: false,
        ),
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
    test('schemaVersion is 4', () {
      expect(SettingsModel.schemaVersion, 4);
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

  group('SettingsModel.bindingsSeeded (W3-002 seed migration)', () {
    test('defaults() is already seeded (fresh install needs no migration)', () {
      expect(SettingsModel.defaults().bindingsSeeded, isTrue);
    });

    test('fromJson without bindingsSeeded key defaults to false (legacy data)',
        () {
      final SettingsModel decoded =
          SettingsModel.fromJson(const <String, Object?>{'fontSize': 64.0});
      expect(decoded.bindingsSeeded, isFalse);
    });

    test('toJson serialises the bindingsSeeded flag under key bindingsSeeded',
        () {
      final Map<String, Object> json = SettingsModel.defaults().toJson();
      expect(json['bindingsSeeded'], true);
    });

    test('round-trips bindingsSeeded for both true and false', () {
      final SettingsModel seeded = SettingsModel.defaults();
      expect(SettingsModel.fromJson(seeded.toJson()).bindingsSeeded, isTrue);

      final SettingsModel notSeeded =
          SettingsModel.defaults().copyWith(bindingsSeeded: false);
      expect(
        SettingsModel.fromJson(notSeeded.toJson()).bindingsSeeded,
        isFalse,
      );
    });

    test('copyWith flips bindingsSeeded while preserving other fields', () {
      final SettingsModel original = SettingsModel.defaults();
      final SettingsModel updated = original.copyWith(bindingsSeeded: false);
      expect(updated.bindingsSeeded, isFalse);
      expect(updated.fontSize, original.fontSize);
      expect(updated.bindings, original.bindings);
    });

    test('participates in equality and hashCode', () {
      final SettingsModel seeded = SettingsModel.defaults();
      final SettingsModel notSeeded = seeded.copyWith(bindingsSeeded: false);
      expect(seeded == notSeeded, isFalse);
    });
  });

  group('SettingsModel schema golden fixtures (1.4.0-W1-015, SPEC-009 A.1)',
      () {
    // 四組定樁 JSON，逐版對應 SPEC-009 A.1「Schema 版本演進」表。
    // 內容以 `git show <commit>:lib/models/settings_model.dart` 讀出的
    // toJson() 實際輸出欄位集為準（見 Context Bundle「四組 fixture 的界定」），
    // 不依 SPEC 描述推測。新增 schema 版本時新增 fixture，禁止修改既有 fixture。

    // v1（commit bd83aea）：7 欄，無 lifeTimerMode / birthDate / bindings /
    // bindingsSeeded。
    const Map<String, Object> v1Fixture = <String, Object>{
      'schemaVersion': 1,
      'fontSize': 96.0,
      'fillColor': 0xFFAABBCC,
      'strokeColor': 0xFF112233,
      'strokeWidth': 4.0,
      'timeFormat': 'HH:mm:ss',
      'targetScreenIndex': 1,
      'autoLaunch': true,
    };

    // v2（commit afa3d67）：v1 + lifeTimerMode + birthDate。
    const Map<String, Object> v2Fixture = <String, Object>{
      'schemaVersion': 2,
      'fontSize': 96.0,
      'fillColor': 0xFFAABBCC,
      'strokeColor': 0xFF112233,
      'strokeWidth': 4.0,
      'timeFormat': 'HH:mm:ss',
      'targetScreenIndex': 1,
      'autoLaunch': true,
      'lifeTimerMode': true,
      'birthDate': 662688000000,
    };

    // v3-early（commit d05724a，bindingsSeeded 加欄前）：v2 + bindings，
    // 無 bindingsSeeded 鍵。
    const Map<String, Object> v3EarlyFixture = <String, Object>{
      'schemaVersion': 3,
      'fontSize': 96.0,
      'fillColor': 0xFFAABBCC,
      'strokeColor': 0xFF112233,
      'strokeWidth': 4.0,
      'timeFormat': 'HH:mm:ss',
      'targetScreenIndex': 1,
      'autoLaunch': true,
      'lifeTimerMode': true,
      'birthDate': 662688000000,
      'bindings': <Map<String, Object>>[
        <String, Object>{
          'buttonNumber': 3,
          'action': <String, Object>{
            'type': 'dragScroll',
            'direction': 'inverted',
            'sensitivity': 2.5,
          },
        },
        <String, Object>{
          'buttonNumber': 4,
          'action': <String, Object>{
            'type': 'hotkey',
            'keyCode': 12,
            'modifiers': <int>[1, 2],
          },
        },
      ],
    };

    // v3-late（commit 10284df 以後）：v3-early + bindingsSeeded。同版
    // schemaVersion=3，差異僅在鍵是否存在，驗證 _migrateBindingSeed 觸發分支。
    final Map<String, Object> v3LateFixture = <String, Object>{
      ...v3EarlyFixture,
      'bindingsSeeded': true,
    };

    // v4（1.4.0-W1-001.2 落地，SPEC-008 FR-06 / SPEC-009 A.1）：v3-late +
    // 游標定位器三項設定，schemaVersion=4。鍵名與 SettingsModel 實作一致。
    final Map<String, Object> v4Fixture = <String, Object>{
      ...v3LateFixture,
      'schemaVersion': 4,
      'cursorLocatorEnabled': false,
      'cursorLocatorEffectDurationSeconds': 2.0,
      'cursorLocatorPrimaryColor': 0xFF00FF00,
    };

    test('v1 fixture: 7 欄逐一還原，其餘欄位落回 defaults', () {
      final SettingsModel decoded = SettingsModel.fromJson(v1Fixture);
      expect(decoded.fontSize, 96.0);
      expect(decoded.fillColor, const Color(0xFFAABBCC));
      expect(decoded.strokeColor, const Color(0xFF112233));
      expect(decoded.strokeWidth, 4.0);
      expect(decoded.timeFormat, 'HH:mm:ss');
      expect(decoded.targetScreenIndex, 1);
      expect(decoded.autoLaunch, isTrue);
      // v1 無這些欄位，須落回 defaults（bindingsSeeded 例外，見下方說明）。
      expect(decoded.lifeTimerMode, isFalse);
      expect(decoded.birthDate, isNull);
      expect(decoded.bindings, isEmpty);
      // bindingsSeeded 缺鍵時 fallback 為字面 false（非 defaults() 的
      // true），這是 _migrateBindingSeed 的觸發條件（SPEC-009 A.1）。
      expect(decoded.bindingsSeeded, isFalse);
      expect(
        decoded,
        SettingsModel.defaults().copyWith(
          fontSize: 96.0,
          fillColor: const Color(0xFFAABBCC),
          strokeColor: const Color(0xFF112233),
          strokeWidth: 4.0,
          timeFormat: 'HH:mm:ss',
          targetScreenIndex: 1,
          autoLaunch: true,
          bindings: const <MouseBinding>[],
          bindingsSeeded: false,
        ),
      );
    });

    test('v2 fixture: 加 lifeTimerMode / birthDate，bindings 仍落回空清單',
        () {
      final SettingsModel decoded = SettingsModel.fromJson(v2Fixture);
      expect(decoded.fontSize, 96.0);
      expect(decoded.fillColor, const Color(0xFFAABBCC));
      expect(decoded.strokeColor, const Color(0xFF112233));
      expect(decoded.strokeWidth, 4.0);
      expect(decoded.timeFormat, 'HH:mm:ss');
      expect(decoded.targetScreenIndex, 1);
      expect(decoded.autoLaunch, isTrue);
      expect(decoded.lifeTimerMode, isTrue);
      expect(
        decoded.birthDate,
        DateTime.fromMillisecondsSinceEpoch(662688000000),
      );
      expect(decoded.bindings, isEmpty);
      expect(decoded.bindingsSeeded, isFalse);
      expect(
        decoded,
        SettingsModel.defaults().copyWith(
          fontSize: 96.0,
          fillColor: const Color(0xFFAABBCC),
          strokeColor: const Color(0xFF112233),
          strokeWidth: 4.0,
          timeFormat: 'HH:mm:ss',
          targetScreenIndex: 1,
          autoLaunch: true,
          lifeTimerMode: true,
          birthDate: DateTime.fromMillisecondsSinceEpoch(662688000000),
          bindings: const <MouseBinding>[],
          bindingsSeeded: false,
        ),
      );
    });

    test(
        'v3-early fixture: 加 bindings（2 筆），無 bindingsSeeded 鍵 → false',
        () {
      final SettingsModel decoded = SettingsModel.fromJson(v3EarlyFixture);
      expect(decoded.fontSize, 96.0);
      expect(decoded.lifeTimerMode, isTrue);
      expect(
        decoded.birthDate,
        DateTime.fromMillisecondsSinceEpoch(662688000000),
      );
      expect(decoded.bindings, hasLength(2));
      final MouseBinding drag = decoded.bindings[0];
      expect(drag.buttonNumber, 3);
      expect(drag.action, isA<DragScrollAction>());
      final DragScrollAction dragAction = drag.action as DragScrollAction;
      expect(dragAction.direction, ScrollDirection.inverted);
      expect(dragAction.sensitivity, 2.5);
      final MouseBinding hotkey = decoded.bindings[1];
      expect(hotkey.buttonNumber, 4);
      expect(hotkey.action, isA<HotkeyAction>());
      final HotkeyAction hotkeyAction = hotkey.action as HotkeyAction;
      expect(hotkeyAction.keyCode, 12);
      expect(hotkeyAction.modifiers, <int>[1, 2]);
      // bindingsSeeded 鍵不存在（此為 v3-early 與 v3-late 的關鍵差異）。
      expect(v3EarlyFixture.containsKey(AppSettingsKeys.bindingsSeededKey),
          isFalse);
      expect(decoded.bindingsSeeded, isFalse);
    });

    test('v3-late fixture: 加 bindingsSeeded=true，觸發已遷移分支', () {
      final SettingsModel decoded = SettingsModel.fromJson(v3LateFixture);
      expect(decoded.fontSize, 96.0);
      expect(decoded.lifeTimerMode, isTrue);
      expect(
        decoded.birthDate,
        DateTime.fromMillisecondsSinceEpoch(662688000000),
      );
      expect(decoded.bindings, hasLength(2));
      expect(decoded.bindings[0].buttonNumber, 3);
      expect(decoded.bindings[1].buttonNumber, 4);
      // v3-late 與 v3-early 的唯一差異：bindingsSeeded 鍵存在且為 true。
      expect(
          v3LateFixture.containsKey(AppSettingsKeys.bindingsSeededKey), isTrue);
      expect(decoded.bindingsSeeded, isTrue);
    });

    test(
        'v4 fixture: 逐一還原游標定位器三欄，既有欄位不受影響（INV-03）',
        () {
      final SettingsModel decoded = SettingsModel.fromJson(v4Fixture);
      expect(decoded.fontSize, 96.0);
      expect(decoded.fillColor, const Color(0xFFAABBCC));
      expect(decoded.strokeColor, const Color(0xFF112233));
      expect(decoded.strokeWidth, 4.0);
      expect(decoded.timeFormat, 'HH:mm:ss');
      expect(decoded.targetScreenIndex, 1);
      expect(decoded.autoLaunch, isTrue);
      expect(decoded.lifeTimerMode, isTrue);
      expect(
        decoded.birthDate,
        DateTime.fromMillisecondsSinceEpoch(662688000000),
      );
      expect(decoded.bindings, hasLength(2));
      expect(decoded.bindingsSeeded, isTrue);
      expect(decoded.cursorLocatorEnabled, isFalse);
      expect(decoded.cursorLocatorEffectDurationSeconds, 2.0);
      expect(decoded.cursorLocatorPrimaryColor, const Color(0xFF00FF00));
    });

    test('fromJson v3-early (缺游標定位器三欄) 補預設值不拋例外', () {
      final SettingsModel decoded = SettingsModel.fromJson(v3EarlyFixture);
      expect(decoded.cursorLocatorEnabled, isTrue);
      expect(decoded.cursorLocatorEffectDurationSeconds, 1.5);
      expect(decoded.cursorLocatorPrimaryColor, const Color(0xFF2196F3));
    });

    test('fromJson v3-late (缺游標定位器三欄) 補預設值不拋例外', () {
      final SettingsModel decoded = SettingsModel.fromJson(v3LateFixture);
      expect(decoded.cursorLocatorEnabled, isTrue);
      expect(decoded.cursorLocatorEffectDurationSeconds, 1.5);
      expect(decoded.cursorLocatorPrimaryColor, const Color(0xFF2196F3));
    });
  });

  group('SettingsModel cursor locator fields (schema v4, SPEC-008 FR-06)', () {
    test('defaults to enabled / 1.5s / system blue', () {
      final SettingsModel d = SettingsModel.defaults();
      expect(d.cursorLocatorEnabled, isTrue);
      expect(d.cursorLocatorEffectDurationSeconds, 1.5);
      expect(d.cursorLocatorPrimaryColor, const Color(0xFF2196F3));
    });

    test('round-trips 三欄位（fromJson(model.toJson()) == model）', () {
      final SettingsModel original = SettingsModel.defaults().copyWith(
        cursorLocatorEnabled: false,
        cursorLocatorEffectDurationSeconds: 2.5,
        cursorLocatorPrimaryColor: const Color(0xFFFF00FF),
      );
      final SettingsModel decoded =
          SettingsModel.fromJson(original.toJson());
      expect(decoded, original);
      expect(decoded.cursorLocatorEnabled, isFalse);
      expect(decoded.cursorLocatorEffectDurationSeconds, 2.5);
      expect(decoded.cursorLocatorPrimaryColor, const Color(0xFFFF00FF));
    });

    test('copyWith 更新三欄位並保留其他欄位', () {
      final SettingsModel original = SettingsModel.defaults();
      final SettingsModel updated = original.copyWith(
        cursorLocatorEnabled: false,
      );
      expect(updated.cursorLocatorEnabled, isFalse);
      expect(
        updated.cursorLocatorEffectDurationSeconds,
        original.cursorLocatorEffectDurationSeconds,
      );
      expect(
        updated.cursorLocatorPrimaryColor,
        original.cursorLocatorPrimaryColor,
      );
      expect(updated.fontSize, original.fontSize);
    });

    test('participates in equality and hashCode', () {
      final SettingsModel a = SettingsModel.defaults();
      final SettingsModel b = a.copyWith(cursorLocatorEnabled: false);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });
  });

  group(
      'SettingsModel cursorLocatorEffectDurationSeconds 值域夾制 '
      '(1.4.0-W2-010, SPEC-008 FR-06)', () {
    test('低於下限的值夾制為 minDurationSeconds', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{'cursorLocatorEffectDurationSeconds': 0.1},
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.minDurationSeconds,
      );
    });

    test('高於上限的值夾制為 maxDurationSeconds', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{'cursorLocatorEffectDurationSeconds': 5.0},
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.maxDurationSeconds,
      );
    });

    test('恰為下限值不受影響（邊界含在合法範圍內）', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{
          'cursorLocatorEffectDurationSeconds':
              AppCursorLocator.minDurationSeconds,
        },
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.minDurationSeconds,
      );
    });

    test('恰為上限值不受影響（邊界含在合法範圍內）', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{
          'cursorLocatorEffectDurationSeconds':
              AppCursorLocator.maxDurationSeconds,
        },
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.maxDurationSeconds,
      );
    });

    test('範圍內的值不受影響（既有 round-trip 行為維持）', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{'cursorLocatorEffectDurationSeconds': 2.5},
      );
      expect(decoded.cursorLocatorEffectDurationSeconds, 2.5);
    });

    test('NaN 落回預設值，不進入模型', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{'cursorLocatorEffectDurationSeconds': double.nan},
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.defaultDurationSeconds,
      );
    });

    test('正無限大落回預設值，不進入模型', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{
          'cursorLocatorEffectDurationSeconds': double.infinity,
        },
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.defaultDurationSeconds,
      );
    });

    test('負無限大落回預設值，不進入模型', () {
      final SettingsModel decoded = SettingsModel.fromJson(
        <String, Object?>{
          'cursorLocatorEffectDurationSeconds': double.negativeInfinity,
        },
      );
      expect(
        decoded.cursorLocatorEffectDurationSeconds,
        AppCursorLocator.defaultDurationSeconds,
      );
    });
  });

  group(
      'SettingsModel fromJson 降級日誌 '
      '(1.4.0-W1-017, observability-rules 規則 1)', () {
    // 攔截 debugSettingsModelLogSink 以斷言降級日誌是否觸發；每筆測試結束
    // 還原原值，避免污染其他測試（含平行執行的其他 group）。
    late List<String> logMessages;
    late void Function(String) originalSink;

    setUp(() {
      logMessages = <String>[];
      originalSink = debugSettingsModelLogSink;
      debugSettingsModelLogSink = logMessages.add;
    });

    tearDown(() {
      debugSettingsModelLogSink = originalSink;
    });

    test('欄位型別錯誤時記錄含欄位名與實際型別的 warning 日誌', () {
      SettingsModel.fromJson(
        const <String, Object?>{'fontSize': 'not a number'},
      );
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('fontSize'));
      expect(logMessages.single, contains('String'));
    });

    test('多個欄位各自型別錯誤時各記錄一則日誌', () {
      SettingsModel.fromJson(const <String, Object?>{
        'fontSize': 'not a number',
        'autoLaunch': 'maybe',
      });
      expect(logMessages, hasLength(2));
      expect(logMessages.any((String m) => m.contains('fontSize')), isTrue);
      expect(logMessages.any((String m) => m.contains('autoLaunch')), isTrue);
    });

    test('cursorLocatorEffectDurationSeconds 型別錯誤時記錄日誌', () {
      SettingsModel.fromJson(const <String, Object?>{
        'cursorLocatorEffectDurationSeconds': 'not a number',
      });
      expect(logMessages, hasLength(1));
      expect(
        logMessages.single,
        contains('cursorLocatorEffectDurationSeconds'),
      );
    });

    test('bindings 內非 Map 元素被略過並記錄日誌', () {
      SettingsModel.fromJson(<String, Object?>{
        AppSettingsKeys.bindingsKey: <Object?>['not a map'],
      });
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('bindings'));
    });

    test('bindings 內單筆無法解析（未知 action type）被略過並記錄日誌', () {
      SettingsModel.fromJson(<String, Object?>{
        AppSettingsKeys.bindingsKey: <Object>[
          <String, dynamic>{
            AppInputBinding.buttonNumberKey: 4,
            AppInputBinding.actionKey: <String, dynamic>{
              AppInputBinding.actionTypeKey: 'corruptType',
            },
          },
        ],
      });
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('bindings'));
    });

    test('正常解析路徑（所有欄位皆合法）不輸出任何日誌', () {
      final SettingsModel original = SettingsModel.defaults().copyWith(
        fontSize: 90,
        cursorLocatorEffectDurationSeconds: 2.0,
      );
      SettingsModel.fromJson(original.toJson());
      expect(logMessages, isEmpty);
    });

    test('欄位缺失（向後相容的正常情境）不輸出任何日誌', () {
      SettingsModel.fromJson(const <String, Object?>{});
      expect(logMessages, isEmpty);
    });

    test('值域夾制（合法型別但越界）不輸出任何日誌', () {
      SettingsModel.fromJson(
        const <String, Object?>{'cursorLocatorEffectDurationSeconds': 0.1},
      );
      expect(logMessages, isEmpty);
    });

    test('多重欄位型別錯誤仍不拋例外（INV-04 維持）', () {
      expect(
        () => SettingsModel.fromJson(const <String, Object?>{
          'fontSize': <String, Object?>{'nested': 'garbage'},
          'bindings': 'not a list even',
          'cursorLocatorEffectDurationSeconds': <int>[1, 2, 3],
        }),
        returnsNormally,
      );
    });
  });
}

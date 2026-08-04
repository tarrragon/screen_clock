// SettingsController 專屬單元測試（ticket 1.4.0-W2-003）。
//
// 涵蓋 domain-map data-management 的 SettingsController 不變式：
// - 載入後狀態反映持久化值
// - 儲存後持久化值反映當前狀態
// 以及 SPEC-009 A.4 交易邊界：autoLaunch OS 對帳非原子交易
// （persist() 先寫持久層、再設 OS；OS 回報不符時，UI 狀態同步回 OS 真實值並重寫持久層）。
//
// 隔離手段：以 InMemorySettingsService / InMemoryAutoLaunchService 取代真實
// 平台服務（test-assertion-design-rules：持久化層須 mock）。

import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/services/auto_launch_service.dart';
import 'package:screen_clock/services/settings_service.dart';
import 'package:screen_clock/state/settings_controller.dart';

void main() {
  group('SettingsController - 載入反映持久化值', () {
    test('以持久層目前值建立 controller 時，初始 value 等於該值', () {
      final SettingsModel seeded =
          SettingsModel.defaults().copyWith(fontSize: 200);
      final InMemorySettingsService service =
          InMemorySettingsService(seed: seeded);
      final InMemoryAutoLaunchService autoLaunchService =
          InMemoryAutoLaunchService();

      final SettingsController controller = SettingsController(
        initial: seeded,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      expect(controller.value, seeded);
      expect(controller.initial, seeded);
    });
  });

  group('SettingsController - 儲存反映當前狀態', () {
    test('persist() 後持久層儲存內容等於當前 value', () async {
      final SettingsModel initial = SettingsModel.defaults();
      final InMemorySettingsService service =
          InMemorySettingsService(seed: initial);
      final InMemoryAutoLaunchService autoLaunchService =
          InMemoryAutoLaunchService();

      final SettingsController controller = SettingsController(
        initial: initial,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      controller.update((s) => s.copyWith(fontSize: 180));
      await controller.persist();

      final SettingsModel persisted = await service.load();
      expect(persisted.fontSize, 180);
      expect(persisted, controller.value);
    });

    test('update() 傳入等值轉換不觸發 value 變更（去重）', () {
      final SettingsModel initial = SettingsModel.defaults();
      final InMemorySettingsService service =
          InMemorySettingsService(seed: initial);
      final InMemoryAutoLaunchService autoLaunchService =
          InMemoryAutoLaunchService();

      final SettingsController controller = SettingsController(
        initial: initial,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.update((s) => s);

      expect(notifyCount, 0);
      expect(controller.value, initial);
    });

    test('resetToStartup() 還原為啟動時快照，不寫入持久層', () async {
      final SettingsModel initial = SettingsModel.defaults();
      final InMemorySettingsService service =
          InMemorySettingsService(seed: initial);
      final InMemoryAutoLaunchService autoLaunchService =
          InMemoryAutoLaunchService();

      final SettingsController controller = SettingsController(
        initial: initial,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      controller.update((s) => s.copyWith(fontSize: 999));
      controller.resetToStartup();

      expect(controller.value, initial);
      // 未呼叫 persist()，持久層應仍是最初 seed 值。
      final SettingsModel persisted = await service.load();
      expect(persisted, initial);
    });
  });

  group('SettingsController - autoLaunch OS 對帳（SPEC-009 A.4 非原子交易）', () {
    test('OS 回報成功（狀態相符）時，value 與持久層皆維持要求值', () async {
      final SettingsModel initial =
          SettingsModel.defaults().copyWith(autoLaunch: false);
      final InMemorySettingsService service =
          InMemorySettingsService(seed: initial);
      final InMemoryAutoLaunchService autoLaunchService =
          InMemoryAutoLaunchService(initial: false);

      final SettingsController controller = SettingsController(
        initial: initial,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      controller.update((s) => s.copyWith(autoLaunch: true));
      await controller.persist();

      expect(controller.value.autoLaunch, true);
      final SettingsModel persisted = await service.load();
      expect(persisted.autoLaunch, true);
    });

    test('OS 回報失敗（狀態不符）時，UI 狀態同步回 OS 真實值並重寫持久層', () async {
      final SettingsModel initial =
          SettingsModel.defaults().copyWith(autoLaunch: false);
      final InMemorySettingsService service =
          InMemorySettingsService(seed: initial);
      final _RefusingAutoLaunchService autoLaunchService =
          _RefusingAutoLaunchService();

      final SettingsController controller = SettingsController(
        initial: initial,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      controller.update((s) => s.copyWith(autoLaunch: true));
      await controller.persist();

      // OS 拒絕開啟（永遠回傳 false），UI 狀態應同步回 false。
      expect(controller.value.autoLaunch, false);
      final SettingsModel persisted = await service.load();
      expect(persisted.autoLaunch, false);
    });

    test('persist() 先寫持久層再設 OS：即使 OS 對帳失敗，第一次寫入仍先發生（非原子邊界）', () async {
      final SettingsModel initial =
          SettingsModel.defaults().copyWith(autoLaunch: false);
      final _RecordingSettingsService service =
          _RecordingSettingsService(seed: initial);
      final _RecordingAutoLaunchService autoLaunchService =
          _RecordingAutoLaunchService(resultOverride: false);

      final SettingsController controller = SettingsController(
        initial: initial,
        service: service,
        autoLaunchService: autoLaunchService,
      );

      controller.update((s) => s.copyWith(autoLaunch: true));
      await controller.persist();

      // 依 SPEC-009 A.4：persist() 先寫持久層（含要求值 true），
      // OS 對帳回報不符（false）後才第二次寫回持久層修正。
      expect(autoLaunchService.setEnabledCalls, [true]);
      expect(
        service.saveCallAutoLaunchValues,
        <bool>[true, false],
      );
    });
  });
}

/// 記錄每次 save() 呼叫時 autoLaunch 值序列的假持久化服務，
/// 用於驗證 persist() 先寫持久層、OS 對帳不符後再重寫一次的非原子交易順序。
class _RecordingSettingsService implements SettingsService {
  _RecordingSettingsService({required SettingsModel seed}) : _current = seed;

  SettingsModel _current;
  final List<bool> saveCallAutoLaunchValues = <bool>[];

  @override
  Future<SettingsModel> load() async => _current;

  @override
  Future<void> save(SettingsModel settings) async {
    _current = settings;
    saveCallAutoLaunchValues.add(settings.autoLaunch);
  }
}

/// 永遠拒絕開啟（回傳 false）的假 OS 對帳服務，模擬 OS 對帳失敗情境。
class _RefusingAutoLaunchService implements AutoLaunchService {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<bool> setEnabled(bool enabled) async => false;
}

/// 記錄 setEnabled 呼叫序列、可指定回傳值覆寫的假 OS 對帳服務。
class _RecordingAutoLaunchService implements AutoLaunchService {
  _RecordingAutoLaunchService({required bool resultOverride})
      : _resultOverride = resultOverride;

  final bool _resultOverride;
  final List<bool> setEnabledCalls = <bool>[];

  @override
  Future<bool> isEnabled() async => _resultOverride;

  @override
  Future<bool> setEnabled(bool enabled) async {
    setEnabledCalls.add(enabled);
    return _resultOverride;
  }
}

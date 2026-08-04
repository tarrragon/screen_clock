// DisplayDetector 單元測試（ticket 1.4.0-W2-001）。
//
// 涵蓋 domain-map platform 的 DisplayDetector bundle 不變式：
// - 螢幕清單至少包含主螢幕（listDisplays / resolveTargetDisplay 皆以主螢幕為基準）
// - 熱插拔事件觸發重新偵測（startWatching 訂閱後，screen event 使 DisplayDetector
//   重新查詢螢幕清單，並在目標螢幕消失時觸發 onTargetLost）
//
// 平台通道以 FakeScreenRetrieverPlatform 取代 screen_retriever 的
// MethodChannel 實作，不依賴真實多螢幕環境（見 test-assertion-design-rules.md）。

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever_platform_interface/screen_retriever_platform_interface.dart';

import 'package:screen_clock/platform/display_detector.dart';

/// 取代 screen_retriever 的 MethodChannel 實作，避免依賴真實原生通道。
class _FakeScreenRetrieverPlatform extends ScreenRetrieverPlatform {
  _FakeScreenRetrieverPlatform({
    List<Display> displays = const <Display>[],
    Display? primary,
  })  : _displays = displays,
        _primary = primary;

  List<Display> _displays;
  final Display? _primary;
  bool getAllDisplaysThrows = false;
  bool getPrimaryDisplayThrows = false;

  final StreamController<Map<Object?, Object?>> _eventController =
      StreamController<Map<Object?, Object?>>.broadcast();

  void setDisplays(List<Display> displays) {
    _displays = displays;
  }

  /// 模擬螢幕熱插拔事件（新增/移除螢幕、解析度變更等）。
  void emitScreenEvent(String type) {
    _eventController.add(<Object?, Object?>{'type': type});
  }

  @override
  Stream<Map<Object?, Object?>> get onScreenEventReceiver =>
      _eventController.stream;

  @override
  Future<List<Display>> getAllDisplays() async {
    if (getAllDisplaysThrows) {
      throw Exception('getAllDisplays failed');
    }
    return _displays;
  }

  @override
  Future<Display> getPrimaryDisplay() async {
    if (getPrimaryDisplayThrows || _primary == null) {
      throw Exception('getPrimaryDisplay failed');
    }
    return _primary;
  }

  Future<void> dispose() => _eventController.close();
}

const Display _primaryDisplay = Display(
  id: 'primary',
  size: Size(1920, 1080),
);

const Display _secondaryDisplay = Display(
  id: 'secondary',
  size: Size(1280, 720),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeScreenRetrieverPlatform fakePlatform;
  late DisplayDetector detector;

  setUp(() {
    fakePlatform = _FakeScreenRetrieverPlatform(
      displays: const <Display>[_primaryDisplay, _secondaryDisplay],
      primary: _primaryDisplay,
    );
    ScreenRetrieverPlatform.instance = fakePlatform;
    detector = DisplayDetector();
  });

  tearDown(() async {
    detector.stopWatching();
    await fakePlatform.dispose();
  });

  group('螢幕清單至少包含主螢幕', () {
    test('listDisplays 回傳清單含主螢幕', () async {
      final List<Display> displays = await detector.listDisplays();

      expect(displays, contains(_primaryDisplay));
    });

    test('listDisplays 偵測失敗時回空清單而非拋出例外', () async {
      fakePlatform.getAllDisplaysThrows = true;

      final List<Display> displays = await detector.listDisplays();

      expect(displays, isEmpty);
    });

    test('resolveTargetDisplay(null) 回傳清單第一筆（視為主螢幕）', () async {
      final Display resolved = await detector.resolveTargetDisplay(null);

      expect(resolved, _primaryDisplay);
    });

    test('resolveTargetDisplay 索引越界時 fallback 至主螢幕', () async {
      final Display resolved = await detector.resolveTargetDisplay(99);

      expect(resolved, _primaryDisplay);
    });

    test('resolveTargetDisplay 索引為負數時 fallback 至主螢幕', () async {
      final Display resolved = await detector.resolveTargetDisplay(-1);

      expect(resolved, _primaryDisplay);
    });

    test('resolveTargetDisplay 有效索引時回傳對應螢幕', () async {
      final Display resolved = await detector.resolveTargetDisplay(1);

      expect(resolved, _secondaryDisplay);
    });

    test('listDisplays 為空時 resolveTargetDisplay 回退至安全主螢幕', () async {
      fakePlatform.setDisplays(const <Display>[]);

      final Display resolved = await detector.resolveTargetDisplay(0);

      expect(resolved, _primaryDisplay);
    });

    test('listDisplays 與 getPrimaryDisplay 皆失敗時回傳零尺寸 fallback', () async {
      fakePlatform.setDisplays(const <Display>[]);
      fakePlatform.getPrimaryDisplayThrows = true;

      final Display resolved = await detector.resolveTargetDisplay(0);

      expect(resolved.size, Size.zero);
    });
  });

  group('熱插拔事件觸發重新偵測', () {
    test('目標螢幕仍存在時，事件不觸發 onTargetLost', () async {
      bool lostCalled = false;
      detector.startWatching(
        watchedIndex: 0,
        onTargetLost: () => lostCalled = true,
      );

      fakePlatform.emitScreenEvent('display-added');
      await pumpEventQueue();

      expect(lostCalled, isFalse);
    });

    test('目標螢幕消失（清單縮短）時，事件觸發 onTargetLost', () async {
      bool lostCalled = false;
      detector.startWatching(
        watchedIndex: 1,
        onTargetLost: () => lostCalled = true,
      );

      // 模擬熱插拔：次要螢幕被移除，清單只剩主螢幕。
      fakePlatform.setDisplays(const <Display>[_primaryDisplay]);
      fakePlatform.emitScreenEvent('display-removed');
      await pumpEventQueue();

      expect(lostCalled, isTrue);
    });

    test('清單變為空時，事件觸發 onTargetLost', () async {
      bool lostCalled = false;
      detector.startWatching(
        watchedIndex: 0,
        onTargetLost: () => lostCalled = true,
      );

      fakePlatform.setDisplays(const <Display>[]);
      fakePlatform.emitScreenEvent('display-removed');
      await pumpEventQueue();

      expect(lostCalled, isTrue);
    });

    test('stopWatching 後事件不再觸發 onTargetLost', () async {
      bool lostCalled = false;
      detector.startWatching(
        watchedIndex: 1,
        onTargetLost: () => lostCalled = true,
      );
      detector.stopWatching();

      fakePlatform.setDisplays(const <Display>[_primaryDisplay]);
      fakePlatform.emitScreenEvent('display-removed');
      await pumpEventQueue();

      expect(lostCalled, isFalse);
    });

    test('重複呼叫 startWatching 改用最新 watchedIndex 判定目標存亡', () async {
      bool secondLost = false;
      // 第一次註冊 watchedIndex: 0；第二次呼叫應取代為 watchedIndex: 1，
      // 判定基準改用最新索引（screen_retriever 底層訂閱行為見套件本身，
      // 不在本測試驗證範圍內）。
      detector.startWatching(
        watchedIndex: 0,
        onTargetLost: () {},
      );
      detector.startWatching(
        watchedIndex: 1,
        onTargetLost: () => secondLost = true,
      );

      // 主螢幕（index 0）仍在清單中；次要螢幕（index 1）消失。
      fakePlatform.setDisplays(const <Display>[_primaryDisplay]);
      fakePlatform.emitScreenEvent('display-removed');
      await pumpEventQueue();

      expect(secondLost, isTrue, reason: '最新註冊的 watchedIndex 應被使用');
    });

    test('事件處理中重新查詢螢幕清單發生例外時不外洩', () async {
      detector.startWatching(
        watchedIndex: 0,
        onTargetLost: () {},
      );

      fakePlatform.getAllDisplaysThrows = true;
      // listDisplays 內部已捕捉例外並回空清單，故 emitScreenEvent 不應拋出。
      expect(
        () => fakePlatform.emitScreenEvent('display-changed'),
        returnsNormally,
      );
      await pumpEventQueue();
    });
  });
}

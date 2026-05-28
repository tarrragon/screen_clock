import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// 螢幕偵測與目標螢幕解析（SPEC-003 FR-01 ~ FR-05）。
///
/// 行為摘要：
/// - [listDisplays] 取得所有可用螢幕；失敗回空清單（FR-04）
/// - [resolveTargetDisplay] 依 CLI 引數選擇目標；無效 / 越界 fallback 主螢幕（FR-04）
/// - [startWatching] 訂閱熱插拔事件；目標螢幕消失時觸發 onTargetLost（FR-05）
///
/// MVP 階段不支援設定面板，故沒有「動態切換目標」介面；
/// 切換目標螢幕需重啟 app（SPEC-003 設計約束）。
class DisplayDetector {
  DisplayDetector({ScreenRetriever? retriever})
      : _retriever = retriever ?? screenRetriever;

  final ScreenRetriever _retriever;
  _DisplayChangeListener? _listener;
  int? _watchedIndex;

  /// 取得所有可用螢幕。失敗回空清單並 log warning（FR-01 / FR-04）。
  Future<List<Display>> listDisplays() async {
    try {
      return await _retriever.getAllDisplays();
    } catch (error, stack) {
      _warn('listDisplays failed; treating as no displays', error, stack);
      return const <Display>[];
    }
  }

  /// 依 [requestedIndex] 選目標螢幕；範圍外 / null / 偵測失敗皆 fallback 主螢幕。
  ///
  /// 回傳的 [Display] 用 `size <= 0` 表示偵測完全失敗，呼叫端 main.dart
  /// 會檢查後套用 fallback 視窗尺寸（FR-04）。
  Future<Display> resolveTargetDisplay(int? requestedIndex) async {
    final List<Display> displays = await listDisplays();
    if (displays.isEmpty) {
      return _safePrimary();
    }
    if (requestedIndex == null) {
      return displays.first;
    }
    if (requestedIndex < 0 || requestedIndex >= displays.length) {
      _warn(
        'requested display index $requestedIndex out of range '
        '(have ${displays.length}); fallback to primary',
        null,
        null,
      );
      return displays.first;
    }
    return displays[requestedIndex];
  }

  /// 訂閱螢幕變更事件。當目標螢幕（index = [watchedIndex]）從清單消失時觸發 [onTargetLost]。
  ///
  /// 新增螢幕 / 其他變更僅 log，不主動切換（SPEC-003 設計約束）。
  void startWatching({
    required int watchedIndex,
    required VoidCallback onTargetLost,
  }) {
    stopWatching();
    _watchedIndex = watchedIndex;
    final listener = _DisplayChangeListener(
      onChange: (String eventName) async {
        try {
          final List<Display> displays = await listDisplays();
          final int currentIndex = _watchedIndex ?? 0;
          if (displays.isEmpty || currentIndex >= displays.length) {
            onTargetLost();
          } else {
            debugPrint(
              '[DisplayDetector] screen event "$eventName" observed; '
              'target index $currentIndex still present, no action',
            );
          }
        } catch (error, stack) {
          _warn('screen change handler error', error, stack);
        }
      },
    );
    _listener = listener;
    _retriever.addListener(listener);
  }

  void stopWatching() {
    final _DisplayChangeListener? listener = _listener;
    if (listener != null) {
      _retriever.removeListener(listener);
    }
    _listener = null;
    _watchedIndex = null;
  }

  Future<Display> _safePrimary() async {
    try {
      return await _retriever.getPrimaryDisplay();
    } catch (error, stack) {
      _warn('primary display detection failed', error, stack);
      return const Display(id: 'fallback', size: Size.zero);
    }
  }

  void _warn(String message, Object? error, StackTrace? stack) {
    debugPrint('[DisplayDetector] WARN $message; error=$error');
    if (stack != null) {
      debugPrint(stack.toString());
    }
  }
}

class _DisplayChangeListener with ScreenListener {
  _DisplayChangeListener({required this.onChange});

  final Future<void> Function(String eventName) onChange;

  @override
  void onScreenEvent(String eventName) {
    onChange(eventName);
  }
}

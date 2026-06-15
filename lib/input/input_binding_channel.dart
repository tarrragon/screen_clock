import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_constants.dart';
import 'mouse_binding.dart';

/// 原生輸入綁定橋接（SPEC-007 FR-07，ticket 1.3.0-W2-001）。
///
/// 將 Dart 端的輔助使用授權查詢 / 請求與綁定下傳，橋接到原生
/// macos/Runner/MainFlutterWindow.swift 的 input_binding method channel。
///
/// 本階段為基礎骨架：原生端 updateBindings 僅儲存綁定、不建立 CGEventTap
/// （event tap 整合留 W2-003）。授權狀態變化由原生經 [onPermissionChanged]
/// 回報，由面板層（FR-07/FR-08）切換引導與功能啟用狀態。
class InputBindingChannel {
  InputBindingChannel({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel(AppInputBinding.channelName);

  final MethodChannel _channel;

  /// 授權狀態變化回呼。參數為「是否已取得輔助使用授權」。
  ValueChanged<bool>? _onPermissionChanged;

  /// 開始監聽原生授權狀態變化通知。
  ///
  /// [onPermissionChanged] 在每次原生回報授權狀態變化時呼叫（true=已授權）。
  void start({required ValueChanged<bool> onPermissionChanged}) {
    _onPermissionChanged = onPermissionChanged;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// 停止監聽並清除 handler。
  void stop() {
    _onPermissionChanged = null;
    _channel.setMethodCallHandler(null);
  }

  /// 查詢目前是否已取得輔助使用授權（AXIsProcessTrusted）。
  ///
  /// 原生回傳非 bool 或呼叫失敗時保守視為未授權，避免誤判為可用而後續崩潰。
  Future<bool> queryPermission() async {
    final Object? result =
        await _invoke(AppInputBinding.queryPermissionMethod);
    return result is bool && result;
  }

  /// 觸發系統授權提示（AXIsProcessTrustedWithOptions）。
  ///
  /// 回傳查詢當下的授權狀態；使用者於系統設定操作後的最終結果由
  /// [onPermissionChanged] 通知，呼叫端不應以此回傳值當作最終授權。
  Future<bool> requestPermission() async {
    final Object? result =
        await _invoke(AppInputBinding.requestPermissionMethod);
    return result is bool && result;
  }

  /// 下傳綁定清單到原生端（本階段僅儲存，不建立 tap）。
  Future<void> updateBindings(List<MouseBinding> bindings) async {
    final List<Map<String, Object>> payload =
        bindings.map((MouseBinding binding) => binding.toJson()).toList();
    await _invoke(
      AppInputBinding.updateBindingsMethod,
      <String, Object>{AppInputBinding.bindingsArgKey: payload},
    );
  }

  /// 統一 invokeMethod 包裝，PlatformException 時記錄並回傳 null，避免拋出
  /// 中斷面板流程（FR-07 NFR-02：權限缺失需安全停用而非崩潰）。
  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('[input-binding] $method 失敗: ${error.message}');
      return null;
    } on MissingPluginException catch (error) {
      debugPrint('[input-binding] $method 無原生處理: ${error.message}');
      return null;
    }
  }

  /// 處理原生端 method call；僅認得授權狀態變化方法。
  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != AppInputBinding.onPermissionChangedMethod) {
      debugPrint('[input-binding] 未知原生方法: ${call.method}');
      return;
    }
    final bool granted = _parseGranted(call.arguments);
    _onPermissionChanged?.call(granted);
  }

  /// 從原生參數解析 granted 旗標；型別不符時保守視為未授權。
  bool _parseGranted(Object? arguments) {
    if (arguments is Map) {
      final Object? value = arguments[AppInputBinding.grantedArgKey];
      if (value is bool) {
        return value;
      }
    }
    debugPrint('[input-binding] 參數格式異常: $arguments');
    return false;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_constants.dart';
import '../input/input_binding_controller.dart';
import '../input/mouse_action.dart';
import '../input/mouse_binding.dart';
import '../models/settings_model.dart';
import '../state/settings_controller.dart';
import '../state/settings_scope.dart';

/// 設定面板（SPEC-005 FR-03 / FR-04 + SPEC-007 FR-07 / FR-08）。
///
/// 九個樣式欄位對應 [SettingsModel]；變更走 [SettingsController.update]
/// → InheritedNotifier rebuild → CenterClock 即時預覽。
///
/// 綁定管理區（FR-07/FR-08）：監聽 [InputBindingController.permissionGranted]
/// 顯示授權狀態與引導；列出現有綁定並可即時刪除。樣式欄位走 Save/Cancel
/// 暫存模型，綁定刪除走即時持久化（FR-08）與 Save/Cancel 解耦。
///
/// 「儲存」呼叫 [SettingsController.persist] 後關閉；
/// 「取消」呼叫 [SettingsController.resetToStartup] 後關閉。
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.availableScreenCount,
    required this.inputBindingController,
    required this.onClose,
  });

  /// 目前可選擇的螢幕數，用於 dropdown 上限（SPEC-005 FR-03 + SPEC-003 FR-01）。
  final int availableScreenCount;

  /// 滑鼠綁定控制器，供權限引導（FR-07）與綁定清單刪除（FR-08）使用。
  final InputBindingController inputBindingController;

  /// 關閉面板的回呼。
  ///
  /// 面板是 Stack overlay（非 Navigator route），不能用 `Navigator.pop` 關閉；
  /// 由上層 `_PanelHost` 注入，內部設 `_panelOpen = false` 並還原 click-through。
  final VoidCallback onClose;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  /// 是否處於新增綁定流程（true 時以 [_AddBindingFlow] 取代「新增綁定」按鈕）。
  bool _addingBinding = false;

  @override
  void initState() {
    super.initState();
    // SPEC-007 FR-07：面板開啟主動刷新授權狀態（空綁定時 notifier 可能仍為 false）。
    widget.inputBindingController.refreshPermission();
  }

  int get availableScreenCount => widget.availableScreenCount;

  VoidCallback get onClose => widget.onClose;

  static const List<String> timeFormats = <String>['HH:mm:ss', 'HH:mm'];

  /// 預設色盤（不透明 RGB 基色，色碼即 Material 對應色）。
  /// 實際套用的透明度由各欄位現有 alpha + 不透明度滑桿決定，不寫死於此。
  static const List<Color> presetColors = <Color>[
    Color(0xFFFFFFFF), // 白
    Color(0xFF000000), // 黑
    Color(0xFFF44336), // 紅
    Color(0xFFFF9800), // 橙
    Color(0xFFFFEB3B), // 黃
    Color(0xFF4CAF50), // 綠
    Color(0xFF2196F3), // 藍
    Color(0xFF9C27B0), // 紫
  ];

  @override
  Widget build(BuildContext context) {
    final SettingsController controller =
        SettingsScope.controllerOf(context);
    final SettingsModel current = SettingsScope.of(context);

    return Center(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 480,
          // 綁定區使面板變高，外層 app 視窗高度有限，包可滾動容器避免 overflow。
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '設定',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _buildFontSize(controller, current),
                    const SizedBox(height: 12),
                    _buildStrokeWidth(controller, current),
                    const SizedBox(height: 12),
                    _buildColorPicker(
                      label: '填色',
                      current: current.fillColor,
                      onPick: (Color c) => controller.update(
                          (SettingsModel s) => s.copyWith(fillColor: c)),
                    ),
                    const SizedBox(height: 12),
                    _buildColorPicker(
                      label: '描邊色',
                      current: current.strokeColor,
                      onPick: (Color c) => controller.update(
                          (SettingsModel s) => s.copyWith(strokeColor: c)),
                    ),
                    const SizedBox(height: 12),
                    _buildTimeFormat(controller, current),
                    const SizedBox(height: 12),
                    _buildTargetScreen(controller, current),
                    const SizedBox(height: 12),
                    _buildAutoLaunch(controller, current),
                    const SizedBox(height: 12),
                    _buildLifeTimer(controller, current),
                    const SizedBox(height: 12),
                    _buildBirthDate(context, controller, current),
                    const SizedBox(height: 24),
                    _buildBindingSection(controller, current),
                    const SizedBox(height: 24),
                    _buildActions(context, controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFontSize(SettingsController controller, SettingsModel current) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('字型大小')),
        Expanded(
          child: Slider(
            min: 40,
            max: 240,
            value: current.fontSize,
            label: current.fontSize.round().toString(),
            divisions: 200,
            onChanged: (double v) => controller
                .update((SettingsModel s) => s.copyWith(fontSize: v)),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(current.fontSize.round().toString()),
        ),
      ],
    );
  }

  Widget _buildStrokeWidth(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('描邊寬度')),
        Expanded(
          child: Slider(
            min: 0,
            max: 8,
            value: current.strokeWidth,
            label: current.strokeWidth.toStringAsFixed(1),
            divisions: 80,
            onChanged: (double v) => controller
                .update((SettingsModel s) => s.copyWith(strokeWidth: v)),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(current.strokeWidth.toStringAsFixed(1)),
        ),
      ],
    );
  }

  Widget _buildColorPicker({
    required String label,
    required Color current,
    required ValueChanged<Color> onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(width: 80, child: Text(label)),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final Color preset in presetColors)
                    _ColorSwatch(
                      color: preset,
                      selected: _sameRgb(preset, current),
                      // 只換 RGB，保留目前 alpha（填色 0C / 描邊 0A 不被覆蓋）。
                      onTap: () => onPick(preset.withValues(alpha: current.a)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            const SizedBox(width: 80, child: Text('不透明度', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                min: 0,
                max: 1,
                value: current.a,
                label: '${(current.a * 100).round()}%',
                divisions: 100,
                // 只換 alpha，保留目前 RGB。
                onChanged: (double v) => onPick(current.withValues(alpha: v)),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('${(current.a * 100).round()}%'),
            ),
          ],
        ),
      ],
    );
  }

  /// 比較兩色 RGB 是否相同（忽略 alpha），用於色盤選中標記。
  static bool _sameRgb(Color a, Color b) {
    return a.r == b.r && a.g == b.g && a.b == b.b;
  }

  Widget _buildTimeFormat(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('時間格式')),
        DropdownButton<String>(
          value: current.timeFormat,
          items: <DropdownMenuItem<String>>[
            for (final String f in timeFormats)
              DropdownMenuItem<String>(value: f, child: Text(f)),
          ],
          onChanged: (String? v) {
            if (v == null) return;
            controller.update((SettingsModel s) => s.copyWith(timeFormat: v));
          },
        ),
      ],
    );
  }

  Widget _buildTargetScreen(
    SettingsController controller,
    SettingsModel current,
  ) {
    final int max = availableScreenCount > 0 ? availableScreenCount : 1;
    final int safeValue =
        current.targetScreenIndex < max ? current.targetScreenIndex : 0;
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('目標螢幕')),
        DropdownButton<int>(
          value: safeValue,
          items: <DropdownMenuItem<int>>[
            for (int i = 0; i < max; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Text(i == 0 ? '主螢幕' : '螢幕 $i'),
              ),
          ],
          onChanged: (int? v) {
            if (v == null) return;
            controller
                .update((SettingsModel s) => s.copyWith(targetScreenIndex: v));
          },
        ),
        const SizedBox(width: 8),
        const Text('（套用需重啟 app）', style: TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildAutoLaunch(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('開機啟動')),
        Switch(
          value: current.autoLaunch,
          onChanged: (bool v) => controller
              .update((SettingsModel s) => s.copyWith(autoLaunch: v)),
        ),
      ],
    );
  }

  Widget _buildLifeTimer(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('生命計時')),
        Switch(
          value: current.lifeTimerMode,
          onChanged: (bool v) => controller
              .update((SettingsModel s) => s.copyWith(lifeTimerMode: v)),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '顯示即時年齡取代時間',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthDate(
    BuildContext context,
    SettingsController controller,
    SettingsModel current,
  ) {
    final DateTime? birth = current.birthDate;
    final String label = birth == null
        ? '未設定'
        : '${birth.year}-${_pad2(birth.month)}-${_pad2(birth.day)}';
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('出生日期')),
        OutlinedButton(
          onPressed: () => _pickBirthDate(context, controller, birth),
          child: Text(label),
        ),
      ],
    );
  }

  Future<void> _pickBirthDate(
    BuildContext context,
    SettingsController controller,
    DateTime? current,
  ) async {
    final DateTime today = DateTime.now();
    final DateTime initial =
        current ?? DateTime(today.year - 20, today.month, today.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked != null) {
      controller.update((SettingsModel s) => s.copyWith(birthDate: picked));
    }
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');

  /// 滑鼠綁定管理區（SPEC-007 FR-07 權限引導 + FR-08 清單/刪除）。
  Widget _buildBindingSection(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          AppText.bindingSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildPermissionRow(),
        const SizedBox(height: 8),
        _buildBindingList(controller, current),
        const SizedBox(height: 8),
        _buildAddBinding(controller),
      ],
    );
  }

  /// FR-06/FR-08：新增綁定流程。未在新增時顯示「新增綁定」按鈕；
  /// 點擊後 inline 展開 [_AddBindingFlow]（不依賴 Navigator，與面板 overlay 一致）。
  /// 完成確認後 update + persist 即時寫入並下傳原生；取消則丟棄。
  Widget _buildAddBinding(SettingsController controller) {
    if (!_addingBinding) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey<String>('add-binding-button'),
          onPressed: () => setState(() => _addingBinding = true),
          icon: const Icon(Icons.add),
          label: const Text(AppText.bindingAddButton),
        ),
      );
    }
    return _AddBindingFlow(
      inputBindingController: widget.inputBindingController,
      onCancel: () => setState(() => _addingBinding = false),
      onConfirm: (MouseBinding binding) async {
        await _addBinding(controller, binding);
        if (mounted) setState(() => _addingBinding = false);
      },
    );
  }

  /// 新增綁定：附加新綁定後即時持久化。copyWith 內 dedupeBindingsByButton
  /// 會以新綁定覆蓋同 buttonNumber 舊綁定（SPEC-007 FR-01）。
  Future<void> _addBinding(
    SettingsController controller,
    MouseBinding binding,
  ) async {
    controller.update(
      (SettingsModel s) => s.copyWith(
        bindings: <MouseBinding>[...s.bindings, binding],
      ),
    );
    await controller.persist();
  }

  /// FR-07：監聽授權狀態，已授權顯示狀態文字，未授權顯示引導 + 開啟系統授權按鈕。
  Widget _buildPermissionRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.inputBindingController.permissionGranted,
      builder: (BuildContext context, bool granted, Widget? _) {
        if (granted) {
          return Text(
            AppText.permissionGrantedStatus,
            style: const TextStyle(fontSize: 13),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              AppText.permissionDeniedGuide,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            OutlinedButton(
              onPressed: widget.inputBindingController.requestPermission,
              child: const Text(AppText.permissionGrantButton),
            ),
          ],
        );
      },
    );
  }

  /// FR-08：列出現有綁定，每筆顯示按鍵編號 + 動作摘要與刪除鈕。
  Widget _buildBindingList(
    SettingsController controller,
    SettingsModel current,
  ) {
    if (current.bindings.isEmpty) {
      return const Text(
        AppText.bindingListEmpty,
        style: TextStyle(fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final MouseBinding binding in current.bindings)
          _buildBindingRow(controller, binding),
      ],
    );
  }

  Widget _buildBindingRow(SettingsController controller, MouseBinding binding) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${AppText.bindingButtonPrefix} ${binding.buttonNumber}'
            '・${_actionSummary(binding.action)}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          key: ValueKey<String>('delete-binding-${binding.buttonNumber}'),
          tooltip: AppText.bindingDeleteTooltip,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteBinding(controller, binding.buttonNumber),
        ),
      ],
    );
  }

  /// FR-08：刪除指定按鍵綁定後即時持久化（與 Save/Cancel 暫存模型解耦）。
  /// persist 後 main.dart 的 _onSettingsChanged 會自動 syncBindings 下傳原生。
  Future<void> _deleteBinding(
    SettingsController controller,
    int buttonNumber,
  ) async {
    controller.update(
      (SettingsModel s) => s.copyWith(
        bindings: s.bindings
            .where((MouseBinding b) => b.buttonNumber != buttonNumber)
            .toList(),
      ),
    );
    await controller.persist();
  }

  /// 動作摘要文案（集中字面於 AppText，禁硬編中文於 widget）。
  String _actionSummary(MouseAction action) {
    return switch (action) {
      DragScrollAction(:final ScrollDirection direction, :final double sensitivity) =>
        '${AppText.bindingActionDragScroll}'
            '・${_directionLabel(direction)}'
            '・${AppText.bindingSensitivityPrefix} '
            '${sensitivity.toStringAsFixed(1)}',
      HotkeyAction(:final int keyCode, :final List<int> modifiers) =>
        '${AppText.bindingActionHotkey}'
            '・${AppText.bindingKeyCodePrefix} $keyCode'
            '・${AppText.bindingModifierPrefix} ${modifiers.length}',
    };
  }

  String _directionLabel(ScrollDirection direction) {
    return switch (direction) {
      ScrollDirection.natural => AppText.bindingDirectionNatural,
      ScrollDirection.inverted => AppText.bindingDirectionInverted,
    };
  }

  Widget _buildActions(BuildContext context, SettingsController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          onPressed: () {
            controller.resetToStartup();
            onClose();
          },
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            await controller.persist();
            onClose();
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

/// 新增綁定流程的本地階段（SPEC-007 FR-06/FR-08）。
enum _AddStage { capturing, configuring }

/// 新增綁定動作型別（流程內部選擇用，對應 [MouseActionType]）。
enum _AddActionType { dragScroll, hotkey }

/// 新增綁定的 inline 流程子 widget（SPEC-007 FR-06 偵測捕捉 + FR-08 新增）。
///
/// 階段：(1) capturing 偵測按鍵——透過 [InputBindingController.startButtonCapture]
/// 等待側鍵，逾時/取消由 onCancelled 退出；(2) configuring 設定動作型別與參數
/// （DragScroll 方向/靈敏度，或 Hotkey 鍵盤組合），確認後回呼 [onConfirm]。
///
/// 採獨立 stateful widget 隔離流程狀態（避免膨脹 [_SettingsPanelState]，
/// 對齊 W4-003 Phase 4 抽子 widget 提示）。
class _AddBindingFlow extends StatefulWidget {
  const _AddBindingFlow({
    required this.inputBindingController,
    required this.onCancel,
    required this.onConfirm,
  });

  final InputBindingController inputBindingController;
  final VoidCallback onCancel;
  final ValueChanged<MouseBinding> onConfirm;

  @override
  State<_AddBindingFlow> createState() => _AddBindingFlowState();
}

class _AddBindingFlowState extends State<_AddBindingFlow> {
  _AddStage _stage = _AddStage.capturing;
  int? _capturedButton;

  _AddActionType _actionType = _AddActionType.dragScroll;

  ScrollDirection _direction = ScrollDirection.natural;
  double _sensitivity = AppInputBinding.defaultDragScrollSensitivity;

  /// Hotkey 擷取結果：實體鍵碼（W5 對齊原生 virtual keycode，本票僅存）。
  int? _hotkeyCode;
  List<int> _hotkeyModifiers = const <int>[];

  final FocusNode _hotkeyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _beginCapture();
  }

  @override
  void dispose() {
    _hotkeyFocus.dispose();
    super.dispose();
  }

  /// 進入偵測捕捉：請 controller 等待側鍵，捕捉到→進設定階段，逾時/取消→退出流程。
  void _beginCapture() {
    widget.inputBindingController.startButtonCapture(
      onCaptured: (int buttonNumber) {
        if (!mounted) return;
        setState(() {
          _capturedButton = buttonNumber;
          _stage = _AddStage.configuring;
        });
      },
      onCancelled: () {
        // 逾時/取消（無結果結束）：退出整個新增流程，不卡在捕捉視覺（FR-06）。
        if (!mounted) return;
        widget.onCancel();
      },
    );
  }

  void _cancelFlow() {
    widget.inputBindingController.cancelButtonCapture();
    widget.onCancel();
  }

  /// 擷取鍵盤組合：記錄 keyDown 的實體鍵碼與當下修飾鍵集合（HardwareKeyboard）。
  KeyEventResult _onHotkeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final int code = event.physicalKey.usbHidUsage;
    final List<int> modifiers = HardwareKeyboard.instance.physicalKeysPressed
        .map((PhysicalKeyboardKey k) => k.usbHidUsage)
        .where((int usage) => usage != code)
        .toList()
      ..sort();
    setState(() {
      _hotkeyCode = code;
      _hotkeyModifiers = modifiers;
    });
    return KeyEventResult.handled;
  }

  MouseBinding _buildBinding() {
    final MouseAction action = switch (_actionType) {
      _AddActionType.dragScroll =>
        DragScrollAction(direction: _direction, sensitivity: _sensitivity),
      _AddActionType.hotkey =>
        HotkeyAction(keyCode: _hotkeyCode ?? 0, modifiers: _hotkeyModifiers),
    };
    return MouseBinding(buttonNumber: _capturedButton ?? 0, action: action);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _stage == _AddStage.capturing
            ? _buildCapturing()
            : _buildConfiguring(),
      ),
    );
  }

  List<Widget> _buildCapturing() {
    return <Widget>[
      const Text(AppText.bindingCapturePrompt, style: TextStyle(fontSize: 13)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey<String>('add-flow-cancel'),
          onPressed: _cancelFlow,
          child: const Text(AppText.bindingFlowCancel),
        ),
      ),
    ];
  }

  List<Widget> _buildConfiguring() {
    return <Widget>[
      Text(
        '${AppText.bindingCapturedPrefix} $_capturedButton',
        style: const TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 8),
      const Text(AppText.bindingActionTypeLabel, style: TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      _buildActionTypeSelector(),
      const SizedBox(height: 8),
      if (_actionType == _AddActionType.dragScroll)
        ..._buildDragScrollParams()
      else
        ..._buildHotkeyParams(),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            key: const ValueKey<String>('add-flow-cancel'),
            onPressed: _cancelFlow,
            child: const Text(AppText.bindingFlowCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey<String>('add-flow-confirm'),
            onPressed: () => widget.onConfirm(_buildBinding()),
            child: const Text(AppText.bindingFlowConfirm),
          ),
        ],
      ),
    ];
  }

  Widget _buildActionTypeSelector() {
    return Row(
      children: <Widget>[
        ChoiceChip(
          key: const ValueKey<String>('add-flow-type-dragScroll'),
          label: const Text(AppText.bindingActionDragScroll),
          selected: _actionType == _AddActionType.dragScroll,
          onSelected: (_) =>
              setState(() => _actionType = _AddActionType.dragScroll),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          key: const ValueKey<String>('add-flow-type-hotkey'),
          label: const Text(AppText.bindingActionHotkey),
          selected: _actionType == _AddActionType.hotkey,
          onSelected: (_) =>
              setState(() => _actionType = _AddActionType.hotkey),
        ),
      ],
    );
  }

  List<Widget> _buildDragScrollParams() {
    return <Widget>[
      Row(
        children: <Widget>[
          ChoiceChip(
            key: const ValueKey<String>('add-flow-direction-natural'),
            label: const Text(AppText.bindingDirectionNatural),
            selected: _direction == ScrollDirection.natural,
            onSelected: (_) =>
                setState(() => _direction = ScrollDirection.natural),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const ValueKey<String>('add-flow-direction-inverted'),
            label: const Text(AppText.bindingDirectionInverted),
            selected: _direction == ScrollDirection.inverted,
            onSelected: (_) =>
                setState(() => _direction = ScrollDirection.inverted),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          const Text(AppText.bindingSensitivityPrefix,
              style: TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              min: 0.1,
              max: 5,
              divisions: 49,
              value: _sensitivity,
              label: _sensitivity.toStringAsFixed(1),
              onChanged: (double v) => setState(() => _sensitivity = v),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(_sensitivity.toStringAsFixed(1)),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildHotkeyParams() {
    final String captured = _hotkeyCode == null
        ? AppText.bindingHotkeyNotCaptured
        : '${AppText.bindingKeyCodePrefix} $_hotkeyCode'
            '・${AppText.bindingModifierPrefix} ${_hotkeyModifiers.length}';
    return <Widget>[
      Focus(
        focusNode: _hotkeyFocus,
        autofocus: true,
        onKeyEvent: _onHotkeyEvent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(AppText.bindingHotkeyCapturePrompt,
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(captured, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    ];
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/input/mouse_action.dart';
import 'package:screen_clock/input/mouse_binding.dart';

void main() {
  group('DragScrollAction', () {
    test('defaults to natural direction and default sensitivity', () {
      const DragScrollAction action = DragScrollAction();
      expect(action.direction, ScrollDirection.natural);
      expect(action.sensitivity, AppInputBinding.defaultDragScrollSensitivity);
      expect(action.type, MouseActionType.dragScroll);
    });

    test('round-trips through json', () {
      const DragScrollAction original = DragScrollAction(
        direction: ScrollDirection.inverted,
        sensitivity: 2.5,
      );
      final MouseAction? restored =
          MouseAction.fromJson(Map<String, dynamic>.from(original.toJson()));
      expect(restored, original);
    });

    test('copyWith does not mutate the original', () {
      const DragScrollAction original = DragScrollAction();
      final DragScrollAction updated =
          original.copyWith(direction: ScrollDirection.inverted);
      expect(updated.direction, ScrollDirection.inverted);
      expect(original.direction, ScrollDirection.natural);
    });

    test('tolerates missing fields by using defaults', () {
      final MouseAction? restored = MouseAction.fromJson(<String, dynamic>{
        AppInputBinding.actionTypeKey: AppInputBinding.dragScrollType,
      });
      expect(restored, const DragScrollAction());
    });
  });

  group('HotkeyAction', () {
    test('expresses a multi-modifier combination (Cmd+Shift+4)', () {
      final HotkeyAction action =
          HotkeyAction(keyCode: 21, modifiers: <int>[55, 56]);
      expect(action.keyCode, 21);
      expect(action.modifiers, <int>[55, 56]);
      expect(action.type, MouseActionType.hotkey);
    });

    test('round-trips through json', () {
      final HotkeyAction original =
          HotkeyAction(keyCode: 21, modifiers: <int>[55, 56]);
      final MouseAction? restored =
          MouseAction.fromJson(Map<String, dynamic>.from(original.toJson()));
      expect(restored, original);
    });

    test('modifiers list is immutable', () {
      final HotkeyAction action = HotkeyAction(keyCode: 1, modifiers: <int>[2]);
      expect(() => action.modifiers.add(3), throwsUnsupportedError);
    });

    test('copyWith does not mutate the original', () {
      final HotkeyAction original = HotkeyAction(keyCode: 1);
      final HotkeyAction updated = original.copyWith(keyCode: 2);
      expect(updated.keyCode, 2);
      expect(original.keyCode, 1);
    });
  });

  group('MouseAction.fromJson fault tolerance', () {
    test('returns null for unknown type', () {
      final MouseAction? restored = MouseAction.fromJson(<String, dynamic>{
        AppInputBinding.actionTypeKey: 'unknownType',
      });
      expect(restored, isNull);
    });

    test('returns null for missing type', () {
      final MouseAction? restored = MouseAction.fromJson(<String, dynamic>{});
      expect(restored, isNull);
    });
  });

  group('MouseBinding', () {
    test('round-trips through json', () {
      final MouseBinding original = MouseBinding(
        buttonNumber: 3,
        action: HotkeyAction(keyCode: 21, modifiers: <int>[55]),
      );
      final MouseBinding? restored =
          MouseBinding.fromJson(Map<String, dynamic>.from(original.toJson()));
      expect(restored, original);
    });

    test('copyWith does not mutate the original', () {
      const MouseBinding original =
          MouseBinding(buttonNumber: 3, action: DragScrollAction());
      final MouseBinding updated = original.copyWith(buttonNumber: 4);
      expect(updated.buttonNumber, 4);
      expect(original.buttonNumber, 3);
    });

    test('fromJson returns null when buttonNumber is wrong type', () {
      final MouseBinding? restored = MouseBinding.fromJson(<String, dynamic>{
        AppInputBinding.buttonNumberKey: 'not-an-int',
        AppInputBinding.actionKey: const DragScrollAction().toJson(),
      });
      expect(restored, isNull);
    });

    test('fromJson returns null when action is unparseable', () {
      final MouseBinding? restored = MouseBinding.fromJson(<String, dynamic>{
        AppInputBinding.buttonNumberKey: 3,
        AppInputBinding.actionKey: <String, dynamic>{
          AppInputBinding.actionTypeKey: 'bogus',
        },
      });
      expect(restored, isNull);
    });
  });

  group('dedupeBindingsByButton', () {
    test('later binding overrides earlier for same buttonNumber', () {
      final List<MouseBinding> deduped = dedupeBindingsByButton(<MouseBinding>[
        const MouseBinding(buttonNumber: 3, action: DragScrollAction()),
        MouseBinding(buttonNumber: 3, action: HotkeyAction(keyCode: 9)),
      ]);
      expect(deduped.length, 1);
      expect(deduped.single.action, isA<HotkeyAction>());
    });

    test('keeps distinct buttonNumbers', () {
      final List<MouseBinding> deduped = dedupeBindingsByButton(<MouseBinding>[
        const MouseBinding(buttonNumber: 3, action: DragScrollAction()),
        const MouseBinding(buttonNumber: 4, action: DragScrollAction()),
      ]);
      expect(deduped.length, 2);
    });
  });
}

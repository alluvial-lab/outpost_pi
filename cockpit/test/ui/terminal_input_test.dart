// Verify terminal Shift+Enter by tracking the kitty keyboard protocol and
// choosing CSI-u while active or legacy `\n` otherwise.

import 'package:cockpit/app/cockpit/ui/session/terminal_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

TerminalKeyboardEvent _event(
  TerminalKey key, {
  bool shift = false,
  bool ctrl = false,
  bool alt = false,
}) {
  return TerminalKeyboardEvent(
    key: key,
    shift: shift,
    ctrl: ctrl,
    alt: alt,
    state: Terminal(),
    altBuffer: false,
    platform: TerminalTargetPlatform.macos,
  );
}

void main() {
  group('KittyKeyboardTracker', () {
    test('starts inactive', () {
      expect(KittyKeyboardTracker().active, isFalse);
    });

    test('push (CSI > flags u) activates; pop (CSI < u) deactivates', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>7u'); // Pi pushes flags=7 at startup.
      expect(k.active, isTrue);
      k.feed('\x1b[<u'); // Remove on exit.
      expect(k.active, isFalse);
    });

    test('pushing flags 0 does not count as active', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>0u');
      expect(k.active, isFalse);
    });

    test('query (CSI ? u) alone does not activate passive tracking', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[?u');
      expect(k.active, isFalse);
    });

    test('RIS (ESC c) resets state', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>7u');
      expect(k.active, isTrue);
      k.feed('\x1bc');
      expect(k.active, isFalse);
    });

    test('set (CSI = flags ; mode u) turns state on and off', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[=5;1u'); // set flags=5
      expect(k.active, isTrue);
      k.feed('\x1b[=5;3u'); // and-not 5 -> 0
      expect(k.active, isFalse);
    });

    test('sequence split across chunks is still detected', () {
      final k = KittyKeyboardTracker();
      k.feed('arbitrary output\x1b[>');
      expect(k.active, isFalse); // Still incomplete.
      k.feed('7u more output');
      expect(k.active, isTrue);
    });

    test('ordinary text does not activate the protocol accidentally', () {
      final k = KittyKeyboardTracker();
      k.feed('echo \x1b[31mred\x1b[0m and \x1b[2J clear');
      expect(k.active, isFalse);
    });

    test('nested push: pop restores the previous active level', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>1u'); // Level 1.
      k.feed('\x1b[>15u'); // Level 2.
      k.feed('\x1b[<u'); // Return to active level 1.
      expect(k.active, isTrue);
      k.feed('\x1b[<u'); // Remove the last level.
      expect(k.active, isFalse);
    });
  });

  group('ShiftEnterInputHandler', () {
    test('Shift+Enter without kitty -> line feed', () {
      final k = KittyKeyboardTracker();
      final h = ShiftEnterInputHandler(k);
      expect(h(_event(TerminalKey.enter, shift: true)), '\n');
    });

    test('Shift+Enter with kitty active -> CSI 13 ; 2 u', () {
      final k = KittyKeyboardTracker()..feed('\x1b[>7u');
      final h = ShiftEnterInputHandler(k);
      expect(h(_event(TerminalKey.enter, shift: true)), '\x1b[13;2u');
    });

    test(
      'plain Enter without shift falls through to default handler (null)',
      () {
        final h = ShiftEnterInputHandler(KittyKeyboardTracker());
        expect(h(_event(TerminalKey.enter)), isNull);
      },
    );

    test('Ctrl+Shift+Enter and Alt+Shift+Enter are not handled here', () {
      final h = ShiftEnterInputHandler(KittyKeyboardTracker());
      expect(h(_event(TerminalKey.enter, shift: true, ctrl: true)), isNull);
      expect(h(_event(TerminalKey.enter, shift: true, alt: true)), isNull);
    });

    test('other shifted keys are not handled here', () {
      final h = ShiftEnterInputHandler(KittyKeyboardTracker());
      expect(h(_event(TerminalKey.keyA, shift: true)), isNull);
    });
  });
}

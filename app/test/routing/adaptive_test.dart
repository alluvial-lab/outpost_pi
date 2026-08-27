// Plan/tablet — adaptive master-detail shell.
//
// Verifies the three moving parts without spinning up the full DI/boot:
//   1. SessionSelection notifier semantics (select / matches / clear / no-op).
//   2. isWideLayout breakpoint.
//   3. The StatefulShellRoute + navigatorContainerBuilder layout decision:
//      wide → master + detail side by side; narrow → only the active branch.

import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/routing/adaptive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

GoRouter _buildAdaptiveRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute(
        builder: (ctx, st, navShell) => navShell,
        navigatorContainerBuilder: (ctx, navShell, children) {
          if (!canUseTwoPaneLayout(ctx)) return children[navShell.currentIndex];
          return Row(
            children: [
              SizedBox(width: kMasterPaneWidth, child: children[0]),
              Expanded(child: children[1]),
            ],
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('MASTER'))),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/session',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('DETAIL'))),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: _buildAdaptiveRouter()),
  );
  await tester.pumpAndSettle();
}

RemoteSessionRef _ref(String epk, String roomId, String sessionId) =>
    RemoteSessionRef(peerEpk: epk, roomId: roomId, sessionId: sessionId);

void main() {
  group('SessionSelection', () {
    test('starts empty (no pre-selection on launch)', () {
      final sel = SessionSelection();
      expect(sel.current, isNull);
      expect(sel.matches('epk', 'main'), isFalse);
    });

    test('select sets current and matches the canonical session', () {
      final sel = SessionSelection();
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.select(_ref('epkA', 'main', 'session-a'), 'Title A');
      expect(sel.current?.epk, 'epkA');
      expect(sel.current?.roomId, 'main');
      expect(sel.current?.sessionId, 'session-a');
      expect(sel.current?.title, 'Title A');
      expect(sel.matches('epkA', 'main', 'session-a'), isTrue);
      expect(sel.matches('epkA', 'main', 'session-b'), isFalse);
      expect(sel.matches('epkA', 'other', 'session-a'), isFalse);
      expect(sel.matches('epkB', 'main', 'session-a'), isFalse);
      expect(notifications, 1);
    });

    test('re-selecting the same canonical session is a no-op (no rebuild)', () {
      final sel = SessionSelection();
      sel.select(_ref('epkA', 'main', 'session-a'), 'Title A');
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.select(_ref('epkA', 'main', 'session-a'), 'Title A again');
      expect(
        notifications,
        0,
        reason: 'same (epk, room, sessionId) must not notify',
      );
      expect(sel.current?.title, 'Title A', reason: 'unchanged');
    });

    test('same room with a different session id notifies', () {
      final sel = SessionSelection();
      sel.select(_ref('epkA', 'main', 'session-a'), 'Title A');
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.select(_ref('epkA', 'main', 'session-b'), 'Title B');
      expect(notifications, 1);
      expect(sel.current?.sessionId, 'session-b');
    });

    test('clear resets to empty and notifies once', () {
      final sel = SessionSelection();
      sel.select(_ref('epkA', 'main', 'session-a'), 'Title A');
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.clear();
      expect(sel.current, isNull);
      expect(notifications, 1);
      sel.clear(); // already empty
      expect(notifications, 1, reason: 'clearing twice must not re-notify');
    });
  });

  group('isWideLayout — device class by shortestSide (rotation-invariant)', () {
    Future<bool> wideAt(WidgetTester tester, Size size) async {
      late bool wide;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (ctx) {
              wide = isWideLayout(ctx);
              return const SizedBox();
            },
          ),
        ),
      );
      return wide;
    }

    testWidgets(
      'phone landscape stays phone (regression: width>=600 but height<600)',
      (tester) async {
        expect(await wideAt(tester, const Size(932, 430)), isFalse);
      },
    );

    testWidgets('phone portrait is phone', (tester) async {
      expect(await wideAt(tester, const Size(420, 900)), isFalse);
    });

    testWidgets('iPad portrait is tablet', (tester) async {
      expect(await wideAt(tester, const Size(768, 1024)), isTrue);
    });

    testWidgets('iPad landscape is tablet', (tester) async {
      expect(await wideAt(tester, const Size(1024, 768)), isTrue);
    });

    testWidgets('narrow Split View window collapses to phone', (tester) async {
      expect(await wideAt(tester, const Size(400, 1000)), isFalse);
    });

    testWidgets('breakpoint needs BOTH sides >= 600', (tester) async {
      expect(await wideAt(tester, const Size(600, 600)), isTrue);
      expect(
        await wideAt(tester, const Size(599, 1200)),
        isFalse,
        reason: 'one side below 600 → phone',
      );
    });
  });

  group('two-pane pane budget', () {
    Future<bool> splitAt(WidgetTester tester, double width) async {
      late bool split;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: Builder(
            builder: (context) {
              split = canUseTwoPaneLayout(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return split;
    }

    testWidgets('splits only when master and minimum detail both fit', (
      tester,
    ) async {
      const decisions = <(double, bool)>[
        (599, false),
        (600, false),
        (679, false),
        (680, false),
        (681, true),
        (701, true),
        (842, true),
      ];
      for (final (width, expected) in decisions) {
        expect(
          await splitAt(tester, width),
          expected,
          reason: '$width dp pane-budget decision',
        );
      }
    });
  });

  group('adaptive shell layout', () {
    testWidgets('tablet with pane budget → master AND detail', (tester) async {
      await _pumpAt(tester, const Size(1024, 768)); // iPad landscape
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsOneWidget);
    });

    testWidgets('phone portrait → only the active branch (master)', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(420, 900));
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsNothing);
    });

    testWidgets(
      'phone landscape → only master (regression: width 932 >= 600 but it is a '
      'phone, so no two-pane)',
      (tester) async {
        await _pumpAt(tester, const Size(932, 430));
        expect(find.text('MASTER'), findsOneWidget);
        expect(find.text('DETAIL'), findsNothing);
      },
    );
  });

  group('IME inset convergence', () {
    void configurePhoneView(WidgetTester tester, {double inset = 0}) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 797);
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
    }

    List<MethodCall> recordTextInputCalls(
      WidgetTester tester, {
      required bool imeVisible,
    }) {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        imeVisibilityChannel,
        (call) async => call.method == 'isVisible' ? imeVisible : null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          imeVisibilityChannel,
          null,
        );
      });
      return calls;
    }

    testWidgets(
      'single-pane stale inset reasserts hide at the watchdog deadline',
      (tester) async {
        configurePhoneView(tester, inset: 280);
        final calls = recordTextInputCalls(tester, imeVisible: false);

        await tester.pumpWidget(
          const MaterialApp(
            home: PaneCollapseImeDismissal(
              twoPane: false,
              child: SizedBox.expand(),
            ),
          ),
        );
        await tester.pump();
        calls.clear();

        await tester.pump(const Duration(milliseconds: 3999));
        expect(
          calls.where((call) => call.method == 'TextInput.hide'),
          isEmpty,
          reason: 'normal inset animation gets the complete grace interval',
        );

        await tester.pump(const Duration(milliseconds: 1));
        expect(
          calls.where((call) => call.method == 'TextInput.hide'),
          hasLength(1),
          reason:
              'a keyboard-sized inset with no text-input connection must not '
              'pin the single-pane viewport indefinitely',
        );
      },
    );

    testWidgets('focused real keyboard is never dismissed by the watchdog', (
      tester,
    ) async {
      configurePhoneView(tester);
      final calls = recordTextInputCalls(tester, imeVisible: true);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PaneCollapseImeDismissal(
            twoPane: false,
            child: Scaffold(body: TextField(focusNode: focusNode)),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      calls.clear();

      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(
        calls.where((call) => call.method == 'TextInput.hide'),
        isEmpty,
        reason:
            'a nonzero inset plus platform-visible focused editable is a real '
            'IME, not stale WindowManager state',
      );
    });

    testWidgets('focus loss reasserts hide while the inset remains', (
      tester,
    ) async {
      configurePhoneView(tester);
      final calls = recordTextInputCalls(tester, imeVisible: false);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PaneCollapseImeDismissal(
            twoPane: false,
            child: Scaffold(body: TextField(focusNode: focusNode)),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      calls.clear();

      focusNode.unfocus();
      await tester.pump();
      await tester.pump();

      expect(
        calls.where((call) => call.method == 'TextInput.hide'),
        hasLength(2),
        reason:
            'EditableText sends its ordinary close hide; inset hygiene must '
            'reassert it after focus leaves so Android republishes insets',
      );
    });
  });

  group('zero-state collapse', () {
    GoRouter buildGatedRouter() {
      return GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute(
            builder: (ctx, st, navShell) => navShell,
            navigatorContainerBuilder: (ctx, navShell, children) {
              final twoPane =
                  canUseTwoPaneLayout(ctx) &&
                  !ctx.watch<ShellLayout>().isZeroState;
              if (!twoPane) return children[navShell.currentIndex];
              return Row(
                children: [
                  SizedBox(width: kMasterPaneWidth, child: children[0]),
                  Expanded(child: children[1]),
                ],
              );
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (_, _) =>
                        const Scaffold(body: Center(child: Text('MASTER'))),
                  ),
                ],
              ),
              StatefulShellBranch(
                preload: true,
                routes: [
                  GoRoute(
                    path: '/session',
                    builder: (_, _) =>
                        const Scaffold(body: Center(child: Text('DETAIL'))),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    testWidgets(
      'wide + zero-state shows only master; flipping back re-splits',
      (tester) async {
        final shell = ShellLayout()..setZeroState(true);
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1200, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ChangeNotifierProvider<ShellLayout>.value(
            value: shell,
            child: MaterialApp.router(routerConfig: buildGatedRouter()),
          ),
        );
        await tester.pumpAndSettle();

        // Zero-state on a wide screen → single pane (no split).
        expect(find.text('MASTER'), findsOneWidget);
        expect(find.text('DETAIL'), findsNothing);

        // Sessions appear → the split returns.
        shell.setZeroState(false);
        await tester.pumpAndSettle();
        expect(find.text('MASTER'), findsOneWidget);
        expect(find.text('DETAIL'), findsOneWidget);
      },
    );
  });

  group('two-pane SafeArea insets (side insets beside the divider)', () {
    // Mirrors app_router's navigatorContainerBuilder two-pane Row. Each pane is
    // a Scaffold whose body is wrapped in SafeArea (like HomePage / ChatPage).
    // The regression: each pane's SafeArea reads the *full screen* padding, so
    // it also insets the edge facing the divider — a phantom horizontal gutter.
    // The fix strips the divider-facing inset per pane via MediaQuery.removePadding.
    //
    // Uses a tablet-class window that also meets the 681dp pane budget; a
    // phone in landscape and a 600–680dp tablet window no longer reach here.
    const masterKey = Key('master-body');
    const detailKey = Key('detail-body');
    const screen = Size(1024, 768); // iPad landscape
    const padLeft = 60.0; // inset side (e.g. camera housing / rounded corner)
    const padRight = 30.0; // opposite-edge inset
    const padTop = 12.0;
    const padBottom = 21.0; // home indicator
    const dividerW = kPaneDividerWidth;

    Widget pane(Key k) => Scaffold(
      body: SafeArea(child: SizedBox.expand(key: k)),
    );

    Widget twoPaneRow({required bool withFix}) {
      Widget left = SizedBox(width: kMasterPaneWidth, child: pane(masterKey));
      Widget right = Expanded(child: pane(detailKey));
      if (withFix) {
        left = SizedBox(
          width: kMasterPaneWidth,
          child: Builder(
            builder: (ctx) => MediaQuery(
              data: masterPaneMediaQueryData(MediaQuery.of(ctx)),
              child: pane(masterKey),
            ),
          ),
        );
        right = Expanded(
          child: Builder(
            builder: (ctx) => MediaQuery.removePadding(
              context: ctx,
              removeLeft: true,
              child: pane(detailKey),
            ),
          ),
        );
      }
      return Row(
        children: [
          left,
          const VerticalDivider(width: dividerW),
          right,
        ],
      );
    }

    Future<void> pumpRow(WidgetTester tester, {required bool withFix}) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: screen,
              padding: EdgeInsets.fromLTRB(
                padLeft,
                padTop,
                padRight,
                padBottom,
              ),
              viewPadding: EdgeInsets.fromLTRB(
                padLeft,
                padTop,
                padRight,
                padBottom,
              ),
            ),
            child: twoPaneRow(withFix: withFix),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('without the fix: phantom gutter beside the divider', (
      tester,
    ) async {
      await pumpRow(tester, withFix: false);
      // Master (left pane) wrongly insets its right → stops short of the divider.
      expect(
        tester.getRect(find.byKey(masterKey)).right,
        kMasterPaneWidth - padRight,
      );
      // Detail (right pane) wrongly insets its left → gap after the divider.
      expect(
        tester.getRect(find.byKey(detailKey)).left,
        kMasterPaneWidth + dividerW + padLeft,
      );
    });

    testWidgets(
      'with the fix: content reaches the divider, outer insets kept',
      (tester) async {
        await pumpRow(tester, withFix: true);
        final master = tester.getRect(find.byKey(masterKey));
        final detail = tester.getRect(find.byKey(detailKey));

        // Divider-facing edges now reach the divider (no phantom gutter).
        expect(
          master.right,
          kMasterPaneWidth,
          reason: 'master fills up to the divider',
        );
        expect(
          detail.left,
          kMasterPaneWidth + dividerW,
          reason: 'detail starts at the divider',
        );

        // Outer screen-edge + top/bottom insets are still honored (surgical).
        expect(master.left, padLeft, reason: 'screen left inset preserved');
        expect(
          detail.right,
          screen.width - padRight,
          reason: 'screen right inset preserved',
        );
        for (final r in [master, detail]) {
          expect(r.top, padTop, reason: 'top inset preserved');
          expect(
            r.bottom,
            screen.height - padBottom,
            reason: 'bottom inset preserved',
          );
        }
      },
    );
  });

  group('two-pane keyboard isolation', () {
    const screen = Size(842, 701);
    const masterBodyKey = Key('keyboard-master-body');
    const masterMediaKey = Key('keyboard-master-media');

    Future<({double height, EdgeInsets viewInsets})> pumpWithKeyboard(
      WidgetTester tester,
      double keyboardInset,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      EdgeInsets? masterViewInsets;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: screen,
              viewPadding: const EdgeInsets.only(bottom: 24),
              padding: EdgeInsets.only(bottom: keyboardInset > 0 ? 0 : 24),
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
            ),
            child: Builder(
              builder: (context) => Row(
                children: [
                  SizedBox(
                    width: kMasterPaneWidth,
                    child: MediaQuery(
                      key: masterMediaKey,
                      data: masterPaneMediaQueryData(MediaQuery.of(context)),
                      child: Builder(
                        builder: (masterContext) {
                          masterViewInsets = MediaQuery.viewInsetsOf(
                            masterContext,
                          );
                          return Scaffold(
                            body: SafeArea(
                              child: SizedBox.expand(key: masterBodyKey),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  const Expanded(child: Scaffold(body: TextField())),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (
        height: tester.getSize(find.byKey(masterBodyKey)).height,
        viewInsets: masterViewInsets!,
      );
    }

    testWidgets('master height stays stable under a detail keyboard', (
      tester,
    ) async {
      final withoutKeyboard = await pumpWithKeyboard(tester, 0);
      final withKeyboard = await pumpWithKeyboard(tester, 280);

      expect(withKeyboard.height, withoutKeyboard.height);
      expect(withKeyboard.viewInsets.bottom, 0);
      expect(withoutKeyboard.viewInsets.bottom, 0);
    });

    testWidgets(
      'master settings modal keeps the real inset while Home stays isolated',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = screen;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        EdgeInsets? homeInsets;
        EdgeInsets? settingsInsets;
        const homeBodyKey = Key('isolated-home-body');
        const settingsListKey = Key('settings-list-probe');
        const settingsFieldKey = Key('settings-relay-field-probe');
        late BuildContext homeContext;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: screen,
                viewInsets: EdgeInsets.only(bottom: 280),
              ),
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => MasterPaneHomeSurface(
                    isolateKeyboard: true,
                    child: Builder(
                      builder: (context) {
                        homeContext = context;
                        homeInsets = MediaQuery.viewInsetsOf(context);
                        return Scaffold(
                          body: SizedBox.expand(key: homeBodyKey),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final homeHeight = tester.getSize(find.byKey(homeBodyKey)).height;

        showModalBottomSheet<void>(
          context: homeContext,
          isScrollControlled: true,
          builder: (context) {
            settingsInsets = MediaQuery.viewInsetsOf(context);
            return FractionallySizedBox(
              heightFactor: 0.92,
              child: Scaffold(
                body: ListView(
                  key: settingsListKey,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: const <Widget>[TextField(key: settingsFieldKey)],
                ),
              ),
            );
          },
        );
        await tester.pumpAndSettle();

        expect(homeInsets?.bottom, 0);
        expect(
          tester.getSize(find.byKey(homeBodyKey)).height,
          homeHeight,
          reason: 'the persistent Home list must not resize',
        );
        expect(settingsInsets?.bottom, 280);
        final settingsList = tester.widget<ListView>(
          find.byKey(settingsListKey),
        );
        expect((settingsList.padding! as EdgeInsets).bottom, 280);
        expect(find.byKey(settingsFieldKey).hitTestable(), findsOneWidget);
      },
    );
  });
}

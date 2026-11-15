import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/widgets/active_focus_controls.dart';

Finder get _stop => find.byKey(const ValueKey('active-focus-stop'));
Finder get _toggle => find.byKey(const ValueKey('active-focus-toggle'));

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets('Timer actions keep full safe touch areas at $diameter dp', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size.square(diameter);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var pauses = 0;
      var stops = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClipOval(
              child: Stack(
                children: [
                  Positioned(
                    top: diameter * .68,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ActiveFocusControls(
                        paused: false,
                        isRest: false,
                        busy: false,
                        compact: diameter < 220,
                        onPauseResume: () => pauses++,
                        onStop: () => stops++,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final center = Offset(diameter / 2, diameter / 2);
      for (final control in [_stop, _toggle]) {
        expect(control.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(control);
        expect(bounds.width, greaterThanOrEqualTo(40));
        expect(bounds.height, greaterThanOrEqualTo(40));
        for (final corner in [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomLeft,
          bounds.bottomRight,
        ]) {
          expect((corner - center).distance, lessThan(diameter / 2));
        }
      }
      expect(tester.getSize(_toggle).width, greaterThanOrEqualTo(72));
      // The outer part of each target works, independently of its icon.
      await tester.tapAt(tester.getRect(_stop).centerLeft + const Offset(4, 0));
      await tester.pump();
      expect(stops, 1);
      expect(pauses, 0);
      await tester.tapAt(
        tester.getRect(_toggle).centerRight - const Offset(4, 0),
      );
      await tester.pump();
      expect(pauses, 1);
      expect(stops, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Pause, resume and rest show consistent labels and colors', (
    tester,
  ) async {
    for (final paused in [false, true]) {
      for (final rest in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ActiveFocusControls(
                  paused: paused,
                  isRest: rest,
                  busy: false,
                  compact: true,
                  onPauseResume: () {},
                  onStop: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.byTooltip(paused ? '继续' : '暂停'), findsOneWidget);
        expect(find.byTooltip(rest ? '结束休息' : '提前结束'), findsOneWidget);
        final button = tester.widget<FilledButton>(_toggle);
        final primary = !paused && !rest;
        expect(
          button.style!.backgroundColor!.resolve({}),
          primary ? AppColors.primary : AppColors.overlay,
        );
        expect(
          button.style!.foregroundColor!.resolve({}),
          primary ? AppColors.background : AppColors.text,
        );
      }
    }
  });

  testWidgets(
    'Busy controls reject taps and large labels stay within targets',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: ActiveFocusControls(
                  paused: true,
                  isRest: false,
                  busy: true,
                  compact: true,
                  onPauseResume: () => calls++,
                  onStop: () => calls++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(_toggle);
      await tester.tap(_stop);
      await tester.pump();
      expect(calls, 0);
      expect(tester.widget<FilledButton>(_toggle).onPressed, isNull);
      expect(tester.widget<IconButton>(_stop).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

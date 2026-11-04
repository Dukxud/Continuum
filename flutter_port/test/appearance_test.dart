import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/aero_appearance.dart';
import 'package:codex_resume_flutter/appearance_dialog.dart';

void main() {
  test('Windows v1.16 appearance schema round-trips without losing settings', () {
    const original = AeroAppearance(
      quota: '#3499FF',
      weekly: 'cyan',
      time: 'violet',
      working: 'amber',
      finish: 2,
      lighting: 1,
      shimmer: 180,
      speed: 250,
      aero: false,
    );
    final restored = AeroAppearance.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.color('quota'), const Color(0xff3499ff));
    expect(restored.toJson().keys, containsAll(
      ['quota', 'weekly', 'time', 'working',
       'finish', 'lighting', 'shimmer', 'speed', 'aero']));
  });

  test('invalid stored values are rejected, never rendered as arbitrary settings', () {
    final result = AeroAppearance.fromJson({
      'quota': '<script>',
      'weekly': '#123456',
      'time': 'blue',
      'working': 'invalid',
      'finish': 99,
      'lighting': -1,
      'shimmer': 500,
      'speed': 0,
      'aero': 'yes',
    });
    expect(result.quota, 'green');
    expect(result.weekly, '#123456');
    expect(result.working, 'amber');
    expect(result.finish, 0);
    expect(result.lighting, 0);
    expect(result.shimmer, 100);
    expect(result.speed, 100);
    expect(result.aero, true);
  });

  testWidgets('both appearance tabs and Done are visible at normal window height', (tester) async {
    tester.view.physicalSize = const Size(900, 566);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    AeroAppearance last = AeroAppearance.defaults;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => Center(child:
        ElevatedButton(onPressed: () {
          showDialog<void>(
            context: context,
            builder: (_) => AeroAppearanceEditor(
              initial: last,
              onChanged: (value) => last = value,
            ),
          );
        }, child: const Text('Open editor')))),
    )));
    await tester.tap(find.text('Open editor'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('5-hour color'), findsOneWidget);
    expect(find.text('Weekly color'), findsOneWidget);
    expect(find.text('Countdown color'), findsOneWidget);
    expect(find.text('Working color'), findsOneWidget);
    expect(find.text('Changes are saved automatically.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Save and close'), findsNothing);
    expect(tester.getBottomRight(find.text('Done')).dy, lessThan(566));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Optics'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Liquid material'), findsOneWidget);
    expect(find.text('Studio lighting'), findsOneWidget);
    expect(find.text('Reflection strength'), findsOneWidget);
    expect(find.text('Reflection speed'), findsOneWidget);
    expect(find.text('Enable Aero Liquid optics'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    // Preserve the Windows accessibility workaround on both sliders.
    expect(find.byType(Overlay), findsAtLeastNWidgets(3));
    expect(find.text('Done'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Done')).dy, lessThan(566));
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 150));
    expect(last.aero, isFalse);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Open editor'), findsOneWidget);
    expect(last.aero, isFalse);
    expect(tester.takeException(), isNull);
  });
}

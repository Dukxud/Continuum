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

  testWidgets('appearance dialog retains every Windows control', (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    AeroAppearance? accepted;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => Center(child:
        ElevatedButton(onPressed: () async {
          accepted = await showDialog<AeroAppearance>(
            context: context,
            builder: (_) => AeroAppearanceEditor(
              initial: const AeroAppearance(),
              onPreview: (_) {},
            ),
          );
        }, child: const Text('Open editor')))),
    )));
    await tester.tap(find.text('Open editor'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Adjust the material. See it change below.'), findsOneWidget);
    expect(find.text('5-hour color'), findsOneWidget);
    expect(find.text('Weekly color'), findsOneWidget);
    expect(find.text('Countdown color'), findsOneWidget);
    expect(find.text('Working color'), findsOneWidget);
    expect(find.text('Save and close'), findsOneWidget);
    // One Navigator overlay plus two local overlays housing the Material
    // sliders. Prevent a regression to bare sliders in the pushed modal.
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.byType(Overlay), findsAtLeastNWidgets(3));
    await tester.tap(find.text('Cancel').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(accepted, isNull);
    expect(tester.takeException(), isNull);
  });
}

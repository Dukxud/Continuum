import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/aero_appearance.dart';
import 'package:codex_resume_flutter/aero_bar.dart';

void main() {
  testWidgets('non-Aero progress bars do not schedule perpetual frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: AeroLiquidBar(
                amount: 71,
                kind: 'quota',
                appearance: AeroAppearance(aero: false),
              ),
            ),
          ),
        ),
      ),
    );
    // Previously an unconditional repeating 100-second ticker meant this
    // could never settle, even with liquid optics deliberately disabled.
    await tester.pumpAndSettle(const Duration(milliseconds: 32));
    expect(find.byType(AeroLiquidBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

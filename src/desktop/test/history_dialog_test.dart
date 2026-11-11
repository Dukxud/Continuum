import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/history_dialog.dart';

const rows = [
  {'Name': 'first-run', 'Status': 'Completed'},
  {'Name': 'second-run', 'Status': 'Failed'},
];

Future<void> openHistory(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function(String) readEvidence,
  Future<void> Function(String)? hideRun,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => HistoryDialog(
                rows: rows,
                readEvidence: readEvidence,
                hideRun: hideRun ?? (_) async {},
              ),
            ),
            child: const Text('Open history'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open history'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('late evidence cannot replace a newer selection', (tester) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    await openHistory(
      tester,
      readEvidence: (name) =>
          name == 'first-run' ? first.future : second.future,
    );
    await tester.tap(find.byType(ListTile).at(0));
    await tester.pump();
    await tester.tap(find.byType(ListTile).at(1));
    await tester.pump();
    second.complete({'Response': 'Current response'});
    await tester.pump();
    first.complete({'Response': 'Stale response'});
    await tester.pumpAndSettle();
    expect(find.text('Current response'), findsOneWidget);
    expect(find.text('Stale response'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a result invalidates its pending evidence read', (
    tester,
  ) async {
    final evidence = Completer<Map<String, dynamic>>();
    final hidden = <String>[];
    await openHistory(
      tester,
      readEvidence: (_) => evidence.future,
      hideRun: (name) async => hidden.add(name),
    );
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.tap(find.text('Remove from history').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    evidence.complete({'Response': 'Removed response'});
    await tester.pumpAndSettle();
    expect(hidden, ['first-run']);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Removed response'), findsNothing);
    expect(find.text('Select a run to inspect its response.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed removal preserves a different selected run', (
    tester,
  ) async {
    final hidden = Completer<void>();
    await openHistory(
      tester,
      readEvidence: (name) async => {'Response': 'Evidence for $name'},
      hideRun: (_) => hidden.future,
    );
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from history').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).at(1));
    await tester.pumpAndSettle();
    hidden.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Evidence for second-run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing history during an evidence read does not update disposed state',
    (tester) async {
      final evidence = Completer<Map<String, dynamic>>();
      await openHistory(tester, readEvidence: (_) => evidence.future);
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      evidence.complete({'Response': 'After closing'});
      await tester.pumpAndSettle();
      expect(find.byType(HistoryDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

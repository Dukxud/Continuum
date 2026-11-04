@Tags(['visual-capture'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' show Tags;
import 'package:codex_resume_flutter/aero_appearance.dart';
import 'package:codex_resume_flutter/appearance_dialog.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/main.dart';

// Review captures are generated only in a separate CI step with
// --update-goldens. They are NOT approved visual reference goldens:
// the widget-test renderer does not reproduce live Windows GPU compositing.
class _SnapshotAdapter implements SchedulerAdapter {
  _SnapshotAdapter({required this.compact, required this.showUpcoming});
  final bool compact;
  final bool showUpcoming;

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    const id = '11111111-1111-1111-1111-111111111111';
    if (action == 'load') {
      return {
        'sessions': [{
          'Id': id,
          'Display': 'Git: BP105-Scheduler-QA | 3 Nov 13:18 | 11111111',
        }],
        'pending': showUpcoming ? [_run()] : [],
        'history': [],
        'settings': {
          'compactMode': compact,
          'barAppearance': const AeroAppearance(aero: false).toJson(),
          'draft': {
            'sessionId': id,
            'model': 'gpt-6.1-sol',
            'effort': 'low',
            'repo': r'C:\Users\Example\source\BP105-Scheduler-QA',
            'message': 'Resume.',
            'access': 'read-only',
          },
        },
        'logDirectory': r'C:\Users\Example\AppData\Local\CodexResumeScheduler',
      };
    }
    if (action == 'usage') {
      return {
        'ok': true,
        'model': payload['model'] ?? 'gpt-6.1-sol',
        'accountId': 'workspace-sha256:' + 'a' * 64,
        'ordinaryUsageAllowed': true,
        'models': [{
          'id': 'gpt-6.1-sol', 'name': 'GPT-6.1-Sol',
          'defaultEffort': 'low', 'isDefault': true,
          'efforts': ['low', 'medium', 'high'],
        }],
        'windows': [
          {'label': '5-hour', 'remainingPercent': 71.0},
          {'label': 'Weekly', 'remainingPercent': 45.0},
        ],
      };
    }
    if (action == 'pending') {
      return {'pending': showUpcoming ? [_run()] : [], 'history': []};
    }
    return {};
  }

  Map<String, dynamic> _run() {
    final when = DateTime.now().add(const Duration(hours: 2));
    return {
      'Name': 'CodexResume-20261103-2100-abcd1234',
      'When': when.toIso8601String(),
      'Status': 'Scheduled',
      'CreatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Model': 'gpt-6.1-sol',
      'Description': 'gpt-6.1-sol / low / read-only | Resume.',
      'Repo': r'C:\Users\Example\source\BP105-Scheduler-QA',
      'Session': '11111111-1111-1111-1111-111111111111',
    };
  }
}

Future<void> _loadWindowsTestFonts() async {
  Future<void> load(String family, File file) async {
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  }
  await load('Segoe UI', File(r'C:\Windows\Fonts\segoeui.ttf'));
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk != null && sdk.isNotEmpty) {
    await load('MaterialIcons',
      File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
  }
}

void main() {
  setUpAll(_loadWindowsTestFonts);

  Future<void> capture(WidgetTester tester, {
    required String name,
    required Size size,
    required bool compact,
    bool showUpcoming = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Segoe UI'),
      home: RepaintBoundary(
        key: const Key('capture'),
        child: SchedulerHome(adapter: _SnapshotAdapter(
          compact: compact, showUpcoming: showUpcoming)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(const Key('capture')),
      matchesGoldenFile('captures/$name.png'));
  }

  testWidgets('full desktop layout', (tester) async {
    await capture(tester, name: 'full', size: const Size(1240, 810),
      compact: false);
  });

  testWidgets('compact quota layout', (tester) async {
    await capture(tester, name: 'compact', size: const Size(540, 495),
      compact: true);
  });

  testWidgets('full layout with upcoming run', (tester) async {
    await capture(tester, name: 'full-upcoming', size: const Size(1240, 810),
      compact: false, showUpcoming: true);
  });

  testWidgets('compact upcoming-run layout', (tester) async {
    await capture(tester, name: 'compact-upcoming', size: const Size(540, 645),
      compact: true, showUpcoming: true);
  });

  testWidgets('appearance editor controls', (tester) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Segoe UI'),
      home: Scaffold(body: RepaintBoundary(
        key: const Key('capture'),
        child: AeroAppearanceEditor(
          initial: const AeroAppearance(aero: false),
          onChanged: (_) {},
        ),
      )),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(const Key('capture')),
      matchesGoldenFile('captures/appearance.png'));
  });
}

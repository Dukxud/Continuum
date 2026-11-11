@Tags(['visual-capture'])
library;

import 'package:codex_resume_flutter/scheduler_home.dart';
import 'package:codex_resume_flutter/app.dart';
import 'package:codex_resume_flutter/aero_bar.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/aero_appearance.dart';
import 'package:codex_resume_flutter/appearance_dialog.dart';
import 'package:codex_resume_flutter/bridge.dart';

// Review captures are generated explicitly with --tags visual-capture
// --update-goldens. All adapter data is synthetic; no Windows bridge is started. They are NOT approved visual reference goldens:
// the widget-test renderer does not reproduce live Windows GPU compositing.
class _SnapshotAdapter implements SchedulerAdapter {
  _SnapshotAdapter({
    required this.compact,
    required this.showUpcoming,
    this.micro = false,
  });
  final bool compact;
  final bool micro;
  final bool showUpcoming;

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    const id = '11111111-1111-1111-1111-111111111111';
    if (action == 'load') {
      return {
        'sessions': [
          {'Id': id, 'Display': 'Continuum | Review the scheduling workflow'},
        ],
        'pending': showUpcoming ? [_run()] : [],
        'history': [],
        'settings': {
          'compactMode': compact,
          'microMode': micro,
          'barAppearance': const AeroAppearance(aero: false).toJson(),
          'draft': {
            'sessionId': id,
            'model': 'gpt-6.1-sol',
            'effort': 'low',
            'repo': r'C:\projects\continuum',
            'message':
                'Review the scheduling workflow and summarize the next steps.',
            'access': 'read-only',
            'executionMode': 'background',
          },
        },
        'logDirectory': r'C:\Users\Example\AppData\Local\CodexResumeScheduler',
      };
    }
    if (action == 'usage') {
      return {
        'ok': true,
        'model': payload['model'] ?? 'gpt-6.1-sol',
        'accountId': 'workspace-sha256:${'a' * 64}',
        'ordinaryUsageAllowed': true,
        'models': [
          {
            'id': 'gpt-6.1-sol',
            'name': 'GPT-6.1-Sol',
            'defaultEffort': 'low',
            'isDefault': true,
            'efforts': ['low', 'medium', 'high'],
          },
        ],
        'windows': [
          {
            'label': '5-hour',
            'remainingPercent': 71.0,
            'resetsAt':
                DateTime.now()
                    .add(const Duration(hours: 3))
                    .millisecondsSinceEpoch ~/
                1000,
          },
          {
            'label': 'Weekly',
            'remainingPercent': 45.0,
            'resetsAt':
                DateTime.now()
                    .add(const Duration(days: 3))
                    .millisecondsSinceEpoch ~/
                1000,
          },
        ],
      };
    }
    if (action == 'select') {
      return {
        'sessionId': id,
        'model': 'gpt-6.1-sol',
        'found': {'Root': r'C:\projects\continuum', 'AlternativeRoots': []},
      };
    }
    if (action == 'pending') {
      return {
        'pending': showUpcoming ? [_run()] : [],
        'history': [],
      };
    }
    return {};
  }

  Map<String, dynamic> _run() {
    final when = DateTime.now().add(const Duration(hours: 2));
    return {
      'Name': 'CodexResume-20261111-2100-abcd1234',
      'When': when.toIso8601String(),
      'Status': 'Scheduled',
      'CreatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Model': 'gpt-6.1-sol',
      'Description':
          'gpt-6.1-sol / low / read-only | Review the scheduling workflow.',
      'Repo': r'C:\projects\continuum',
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
    await load(
      'MaterialIcons',
      File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
    );
  }
}

// Read the production app configuration so capture styling follows the app.
Widget _captureApp(Widget home) => Builder(
  builder: (context) {
    final app = const SchedulerApp().build(context) as MaterialApp;
    return MaterialApp(
      theme: app.theme,
      localizationsDelegates: app.localizationsDelegates,
      supportedLocales: app.supportedLocales,
      home: home,
    );
  },
);

void main() {
  setUpAll(_loadWindowsTestFonts);

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Size size,
    required bool compact,
    bool showUpcoming = false,
    bool micro = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _captureApp(
        RepaintBoundary(
          key: const Key('capture'),
          child: SchedulerHome(
            adapter: _SnapshotAdapter(
              compact: compact,
              showUpcoming: showUpcoming,
              micro: micro,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await AeroAssets.sprites();
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('capture')),
      matchesGoldenFile('captures/$name.png'),
    );
  }

  testWidgets('full desktop layout', (tester) async {
    await capture(
      tester,
      name: 'full',
      size: const Size(1240, 810),
      compact: false,
    );
  });

  testWidgets('compact quota layout', (tester) async {
    await capture(
      tester,
      name: 'compact',
      size: const Size(540, 495),
      compact: true,
    );
  });

  testWidgets('full layout with upcoming run', (tester) async {
    await capture(
      tester,
      name: 'full-upcoming',
      size: const Size(1240, 810),
      compact: false,
      showUpcoming: true,
    );
  });

  testWidgets('compact upcoming-run layout', (tester) async {
    await capture(
      tester,
      name: 'compact-upcoming',
      size: const Size(540, 645),
      compact: true,
      showUpcoming: true,
    );
  });

  testWidgets('micro quota layout', (tester) async {
    await capture(
      tester,
      name: 'micro',
      size: const Size(392, 212),
      compact: true,
      micro: true,
    );
  });

  testWidgets('appearance editor controls', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _captureApp(
        Scaffold(
          body: RepaintBoundary(
            key: const Key('capture'),
            child: AeroAppearanceEditor(
              initial: const AeroAppearance(aero: false),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await AeroAssets.sprites();
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('capture')),
      matchesGoldenFile('captures/appearance-colors.png'),
    );
    await tester.tap(find.text('Optics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('capture')),
      matchesGoldenFile('captures/appearance-optics.png'),
    );
  });
}

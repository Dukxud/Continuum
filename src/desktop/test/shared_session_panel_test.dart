import 'package:codex_resume_flutter/shared_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/scheduler_controller.dart';

const job = 'CodexResume-20261105-1737-8fea70e0';

class SharedFixtureAdapter implements SchedulerAdapter {
  int stage = 0, viewerOpens = 0;
  bool archived = false;
  final List<Map<String, dynamic>> responses = [];
  final List<String> actions = [];
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    actions.add(action);
    if (action == 'shared-status') {
      if (archived) {
        return {
          'status': 'completed',
          'offline': true,
          'pending': <Map<String, dynamic>>[],
          'events': <Map<String, dynamic>>[],
        };
      }
      final pending = switch (stage) {
        0 => [
          {
            'id': '101',
            'method': 'item/tool/requestUserInput',
            'params': {
              'threadId': '11111111-2222-3333-4444-555555555555',
              'questions': [
                {
                  'id': 'choice',
                  'question': 'Proceed?',
                  'options': [
                    {'label': 'Yes'},
                    {'label': 'No'},
                  ],
                },
              ],
            },
          },
        ],
        1 => [
          {
            'id': '102',
            'method': 'item/commandExecution/requestApproval',
            'params': {
              'reason': 'Run repository tests?',
              'command': 'npm test',
            },
          },
        ],
        _ => <Map<String, dynamic>>[],
      };
      return {
        'status': stage >= 2 ? 'completed' : 'needs-input',
        'pending': pending,
        'events': [
          {'kind': 'text', 'text': 'Visible Codex stream.'},
        ],
      };
    }
    if (action == 'shared-open') {
      viewerOpens++;
      return {'opened': true, 'nativeTui': true};
    }
    if (action == 'shared-answer') {
      responses.add(payload);
      stage++;
      return {'action': 'ack'};
    }
    throw StateError('Unexpected privileged action: $action');
  }
}

void main() {
  testWidgets(
    'shared session shows Codex questions, explicit approvals and viewer',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final adapter = SharedFixtureAdapter();
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharedSessionPanel(controller: controller, name: job),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Proceed?'), findsOneWidget);
      expect(find.text('Visible Codex stream.'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pump();
      await tester.tap(find.text('Send answers'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.responses.single['requestId'], '101');
      expect((adapter.responses.single['result'] as Map)['answers'], {
        'choice': {
          'answers': ['Yes'],
        },
      });

      expect(find.text('COMMAND APPROVAL'), findsOneWidget);
      expect(find.text('npm test'), findsOneWidget);
      await tester.tap(find.text('Approve once'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.responses.last['requestId'], '102');
      expect(adapter.responses.last['result'], {'decision': 'accept'});
      expect(find.text('Codex: completed'), findsOneWidget);

      expect(find.text('Open Codex Terminal'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shared-open-terminal')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.viewerOpens, 1);
      adapter.archived = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('shared-owner-closed')), findsOneWidget);
      expect(find.text('Codex: completed'), findsOneWidget);
      expect(find.text('Visible Codex stream.'), findsOneWidget);
      final terminalButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('shared-open-terminal')),
      );
      expect(terminalButton.onPressed, isNull);
      expect(
        adapter.actions.every(
          (action) => const [
            'shared-status',
            'shared-answer',
            'shared-open',
          ].contains(action),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

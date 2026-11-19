import 'dart:convert';
import 'dart:io';

import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/scheduler_controller.dart';
import 'package:codex_resume_flutter/windows_scheduler_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const _sessionId = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _verificationError = 'Selected CLI conversation could not be verified.';

String? _findPowerShell() {
  final explicit = Platform.environment['CONTINUUM_TEST_PWSH'];
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final name = Platform.isWindows ? 'pwsh.exe' : 'pwsh';
  final paths = (Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  );
  if (Platform.isWindows) {
    paths.add(
      '${Platform.environment['ProgramFiles'] ?? r'C:\Program Files'}'
      r'\PowerShell\7',
    );
  }
  for (final path in paths) {
    final executable = File('$path${Platform.pathSeparator}$name');
    if (executable.existsSync()) return executable.path;
  }
  return null;
}

/// Selection crosses the same production process/JSON boundary as the Windows
/// host, with the actual dispatcher and backend. Only account quota is a fixture:
/// these tests neither query a user's account nor require Windows Task Scheduler.
class _ReadOnlyBridgeAdapter implements SchedulerAdapter {
  _ReadOnlyBridgeAdapter(this.powerShell, this.fixture);
  final String powerShell;
  final Directory fixture;

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) {
    if (action == 'usage') {
      return Future.value({
        'model': 'test-model',
        'models': [
          {
            'id': 'test-model',
            'efforts': ['medium'],
            'defaultEffort': 'medium',
          },
        ],
        'windows': [],
      });
    }
    return invokeSchedulerProcess(
      action,
      executable: powerShell,
      arguments: [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        File('windows_bridge.ps1').absolute.path,
        '-Action',
        action,
        '-Payload',
        base64Encode(utf8.encode(jsonEncode(payload))),
      ],
      workingDirectory: Directory.current.absolute.path,
      environment: {
        'LOCALAPPDATA': '${fixture.path}/appdata',
        'CODEX_HOME': '${fixture.path}/codex',
      },
    );
  }
}

void main() {
  final powerShell = _findPowerShell();
  group(
    'real PowerShell process boundary',
    () {
      late Directory fixture;
      late _ReadOnlyBridgeAdapter adapter;

      setUp(() {
        fixture = Directory.systemTemp.createTempSync('continuum-transport-');
        Directory('${fixture.path}/appdata').createSync();
        Directory('${fixture.path}/codex/sessions').createSync(recursive: true);
        adapter = _ReadOnlyBridgeAdapter(powerShell!, fixture);
      });
      tearDown(() => fixture.deleteSync(recursive: true));

      SchedulerController selectedController() => SchedulerController(adapter)
        ..ready = true
        ..sessions = [
          {'Id': _sessionId},
        ]
        ..sessionId = _sessionId;

      Future<Map<String, dynamic>> runScript(String script) {
        final file = File('${fixture.path}/response.ps1')
          ..writeAsStringSync(script);
        return invokeSchedulerProcess(
          'select',
          executable: powerShell!,
          arguments: [
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-File',
            file.path,
          ],
          workingDirectory: fixture.path,
        );
      }

      test(
        'the real dispatcher error survives a successful quota refresh',
        () async {
          final controller = selectedController();
          addTearDown(controller.dispose);

          await controller.selectSession(_sessionId);
          expect(controller.error, contains(_verificationError));
          await controller.readUsage();

          expect(controller.error, isNull);
          expect(controller.repositoryWarning, contains(_verificationError));
          expect(controller.repo, isEmpty);
        },
      );

      test(
        'a delayed real process failure cannot replace a manual selection',
        () async {
          final controller = selectedController();
          addTearDown(controller.dispose);

          final lookup = controller.selectSession(_sessionId);
          controller.edit(repository: r'C:\manual\checkout');
          await lookup;
          // Also drain any real isolated preference write the debounce began
          // on a busy host before removing the fixture directory.
          expect(await controller.flushPreferences(), isTrue);

          expect(controller.repo, r'C:\manual\checkout');
          expect(controller.repositoryWarning, isNull);
          expect(controller.error, isNull);
        },
      );

      test('real JSON bridge resolves local Git when App Server metadata is absent', () async {
        final repository = Directory('${fixture.path}/Horizon-élan')
          ..createSync();
        final initialized = await Process.run('git', [
          'init',
          '-q',
          repository.path,
        ]);
        expect(initialized.exitCode, 0, reason: initialized.stderr.toString());
        File(
          '${fixture.path}/codex/sessions/rollout-$_sessionId.jsonl',
        ).writeAsStringSync(
          '${jsonEncode({
            'type': 'session_meta',
            'payload': {'id': _sessionId, 'source': 'cli', 'cwd': repository.path},
          })}\n',
        );

        final result = await adapter.call('select', {'sessionId': _sessionId});
        final found = Map<String, dynamic>.from(result['found'] as Map);
        expect(
          (found['Root'] as String).replaceAll('\\', '/'),
          repository.path.replaceAll('\\', '/'),
        );
      });

      test(
        'non-UTF8 stderr cannot discard an otherwise valid JSON response',
        () async {
          final result = await runScript(r'''
$errorStream = [Console]::OpenStandardError()
$errorStream.Write([byte[]]@(255, 254), 0, 2)
$errorStream.Flush()
[Console]::Out.WriteLine('{"ok":true,"result":{"label":"élan 仓库"}}')
''');
          expect(result['label'], 'élan 仓库');
        },
      );

      test(
        'invalid stdout reports a transport error without echoing process data',
        () async {
          await expectLater(
            runScript(r'''
[Console]::Out.Write('private-payload-marker')
$outputStream = [Console]::OpenStandardOutput()
$outputStream.Write([byte[]]@(255), 0, 1)
$outputStream.Flush()
'''),
            throwsA(
              isA<SchedulerException>()
                  .having(
                    (error) => error.message,
                    'message',
                    contains('UTF-8'),
                  )
                  .having(
                    (error) => error.message,
                    'untrusted process output',
                    isNot(contains('private-payload-marker')),
                  ),
            ),
          );
        },
      );
    },
    skip: powerShell == null
        ? 'PowerShell 7 is required; set CONTINUUM_TEST_PWSH to its executable.'
        : false,
  );
}

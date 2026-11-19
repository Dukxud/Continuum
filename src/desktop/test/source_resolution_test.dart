import 'dart:io';

import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/windows_scheduler_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  setUp(() {
    fixture = Directory.systemTemp.createTempSync(
      'continuum-source-resolution-',
    );
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  Directory directory(String relative) =>
      Directory.fromUri(fixture.uri.resolve(relative))
        ..createSync(recursive: true);

  Directory backend(String relative, {bool engine = true, bool bridge = true}) {
    final result = directory(relative);
    if (engine) {
      File.fromUri(result.uri.resolve('src/backend/CodexRunEngine.ps1'))
          .writeAsStringSyncAfterCreatingParents('fixture backend');
    }
    if (bridge) {
      File.fromUri(result.uri.resolve('src/desktop/windows_bridge.ps1'))
          .writeAsStringSyncAfterCreatingParents('fixture bridge');
    }
    return result;
  }

  test('release uses its adjacent complete bundle over parent and CWD', () {
    backend('parent');
    final bundled = backend('parent/package');
    final unrelated = backend('unrelated');
    expect(
      WindowsSchedulerAdapter.findSourceDirectoryFrom(
        executableDirectory: bundled,
        workingDirectory: unrelated,
        allowWorkingDirectory: false,
      ),
      bundled.path,
    );
  });

  test(
    'release cannot borrow a parent checkout when its bundle is missing',
    () {
      backend('parent');
      final executable = directory('parent/missing-package');
      final unrelated = backend('unrelated');
      expect(
        () => WindowsSchedulerAdapter.findSourceDirectoryFrom(
          executableDirectory: executable,
          workingDirectory: unrelated,
          allowWorkingDirectory: false,
        ),
        throwsA(
          isA<SchedulerException>().having(
            (error) => error.message,
            'actionable package error',
            contains('complete Continuum application package'),
          ),
        ),
      );
    },
  );

  test('release cannot borrow a complete current directory', () {
    final executable = directory('empty-package');
    final unrelated = backend('unrelated');
    expect(
      () => WindowsSchedulerAdapter.findSourceDirectoryFrom(
        executableDirectory: executable,
        workingDirectory: unrelated,
        allowWorkingDirectory: false,
      ),
      throwsA(isA<SchedulerException>()),
    );
  });

  test('an incomplete adjacent bundle cannot fall through to a parent', () {
    backend('parent');
    for (final missingEngine in [false, true]) {
      final incomplete = backend(
        'parent/incomplete-$missingEngine',
        engine: !missingEngine,
        bridge: missingEngine,
      );
      expect(
        () => WindowsSchedulerAdapter.findSourceDirectoryFrom(
          executableDirectory: incomplete,
          workingDirectory: fixture,
          allowWorkingDirectory: false,
        ),
        throwsA(isA<SchedulerException>()),
      );
    }
  });

  test('debug keeps executable ancestor discovery before CWD fallback', () {
    final checkout = backend('checkout');
    final executable = directory('checkout/build/windows/x64/runner/Debug');
    final unrelated = backend('unrelated');
    expect(
      WindowsSchedulerAdapter.findSourceDirectoryFrom(
        executableDirectory: executable,
        workingDirectory: unrelated,
      ),
      checkout.path,
    );
  });

  test(
    'debug keeps current-directory discovery without an adjacent bundle',
    () {
      final executable = directory('toolchain');
      final checkout = backend('checkout');
      expect(
        WindowsSchedulerAdapter.findSourceDirectoryFrom(
          executableDirectory: executable,
          workingDirectory: checkout,
        ),
        checkout.path,
      );
    },
  );

  test(
    'relative override resolves against caller CWD once, not executable',
    () {
      final executable = backend('application');
      backend('application/source');
      final caller = directory('caller');
      final intended = backend('caller/source');
      final resolved = WindowsSchedulerAdapter.findSourceDirectoryFrom(
        executableDirectory: executable,
        workingDirectory: caller,
        sourceOverride: 'source',
        allowWorkingDirectory: false,
      );
      expect(resolved, intended.path);
      expect(Directory(resolved).isAbsolute, isTrue);
      expect(
        File.fromUri(
          Directory(resolved).uri.resolve('src/desktop/windows_bridge.ps1'),
        ).existsSync(),
        isTrue,
        reason: 'Changing the child CWD cannot duplicate the source prefix.',
      );
    },
  );

  test('absolute override is normalized and takes explicit precedence', () {
    final executable = backend('application');
    final intended = backend('backend élan');
    final detour = directory('detour');
    expect(
      WindowsSchedulerAdapter.findSourceDirectoryFrom(
        executableDirectory: executable,
        workingDirectory: fixture,
        sourceOverride:
            '${detour.path}${Platform.pathSeparator}..'
            '${Platform.pathSeparator}${intended.uri.pathSegments.where((part) => part.isNotEmpty).last}',
        allowWorkingDirectory: false,
      ),
      intended.path,
    );
  });

  test(
    'missing or partial explicit override never falls back to valid bundle',
    () {
      final executable = backend('application');
      backend('engine-only', bridge: false);
      backend('bridge-only', engine: false);
      for (final custom in ['missing', 'engine-only', 'bridge-only', '   ']) {
        expect(
          () => WindowsSchedulerAdapter.findSourceDirectoryFrom(
            executableDirectory: executable,
            workingDirectory: fixture,
            sourceOverride: custom,
            allowWorkingDirectory: false,
          ),
          throwsA(
            isA<SchedulerException>().having(
              (error) => error.message,
              'explicit override error',
              contains('CODEX_SCHEDULER_SOURCE'),
            ),
          ),
        );
      }
    },
  );

  test(
    'constructor injection normalizes absolute paths and validates both files',
    () {
      final intended = backend('injected');
      final adapter = WindowsSchedulerAdapter(
        sourceDirectory: '${intended.path}${Platform.pathSeparator}.',
      );
      expect(adapter.sourceDirectory, intended.path);
      final incomplete = backend('injected-incomplete', bridge: false);
      expect(
        () => WindowsSchedulerAdapter(sourceDirectory: incomplete.path),
        throwsA(isA<SchedulerException>()),
      );
    },
  );

  test('relative constructor injection uses current directory and becomes absolute', () {
    // Flutter tests run in the desktop project. This reads the real source
    // markers and changes neither the caller CWD nor environment variables.
    final expected = Directory.current.absolute.parent.parent;
    final adapter = WindowsSchedulerAdapter(sourceDirectory: '../..');
    expect(adapter.sourceDirectory, expected.path);
    expect(Directory(adapter.sourceDirectory).isAbsolute, isTrue);
  });
}

extension on File {
  void writeAsStringSyncAfterCreatingParents(String contents) {
    parent.createSync(recursive: true);
    writeAsStringSync(contents);
  }
}

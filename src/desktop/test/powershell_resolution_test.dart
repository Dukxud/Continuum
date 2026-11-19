import 'dart:io';

import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/windows_scheduler_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('continuum-pwsh-resolution-');
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  File addExecutable(String relativeDirectory) {
    final directory = Directory.fromUri(
      fixture.uri.resolve('$relativeDirectory/'),
    )..createSync(recursive: true);
    return File.fromUri(directory.uri.resolve('pwsh.exe'))
      ..writeAsStringSync('resolver fixture, never executed');
  }

  test('a portable PowerShell on PATH works without Program Files', () {
    final portable = addExecutable('portable PowerShell');
    expect(
      resolveWindowsPowerShell(pathDirectories: [portable.parent.path]),
      portable.path,
    );
  });

  test('PATH order determines the selected existing installation', () {
    final one = addExecutable('first');
    final two = addExecutable('second');
    for (final ordered in [
      [one, two],
      [two, one],
    ]) {
      expect(
        resolveWindowsPowerShell(
          pathDirectories: ordered.map((file) => file.parent.path),
        ),
        ordered.first.path,
      );
    }
  });

  test('PATH wins over both Program Files installations', () {
    final portable = addExecutable('portable');
    addExecutable('Native Program Files/PowerShell/7');
    addExecutable('Program Files/PowerShell/7');
    expect(
      resolveWindowsPowerShell(
        pathDirectories: [portable.parent.path],
        programW6432Directory: Directory.fromUri(
          fixture.uri.resolve('Native Program Files/'),
        ).path,
        programFilesDirectory: Directory.fromUri(
          fixture.uri.resolve('Program Files/'),
        ).path,
      ),
      portable.path,
    );
  });

  test('ProgramW6432 precedes an inherited 32-bit ProgramFiles root', () {
    final native = addExecutable('Native Program Files/PowerShell/7');
    addExecutable('Program Files x86/PowerShell/7');
    expect(
      resolveWindowsPowerShell(
        pathDirectories: [],
        programW6432Directory: Directory.fromUri(
          fixture.uri.resolve('Native Program Files/'),
        ).path,
        programFilesDirectory: Directory.fromUri(
          fixture.uri.resolve('Program Files x86/'),
        ).path,
      ),
      native.path,
    );
  });

  test('ProgramW6432 works when ProgramFiles is absent', () {
    final native = addExecutable('Native Program Files/PowerShell/7');
    expect(
      resolveWindowsPowerShell(
        pathDirectories: [],
        programW6432Directory: Directory.fromUri(
          fixture.uri.resolve('Native Program Files/'),
        ).path,
      ),
      native.path,
    );
  });

  test('a missing native installation falls through to ProgramFiles', () {
    final installed = addExecutable('Program Files/PowerShell/7');
    expect(
      resolveWindowsPowerShell(
        pathDirectories: [],
        programW6432Directory: Directory.fromUri(
          fixture.uri.resolve('missing native root/'),
        ).path,
        programFilesDirectory: Directory.fromUri(
          fixture.uri.resolve('Program Files/'),
        ).path,
      ),
      installed.path,
    );
  });

  test('Program Files is a fallback when PATH has no executable', () {
    final installed = addExecutable('Program Files/PowerShell/7');
    expect(
      resolveWindowsPowerShell(
        pathDirectories: [
          Directory.fromUri(fixture.uri.resolve('missing/')).path,
        ],
        programFilesDirectory: Directory.fromUri(
          fixture.uri.resolve('Program Files/'),
        ).path,
      ),
      installed.path,
    );
  });

  test('quoted absolute paths and spaces preserve the executable path', () {
    final portable = addExecutable('portable with spaces');
    expect(
      resolveWindowsPowerShell(
        pathDirectories: ['  "${portable.parent.path}"  '],
      ),
      portable.path,
    );
  });

  test(
    'empty and relative PATH entries never search the working directory',
    () {
      expect(
        () => resolveWindowsPowerShell(
          pathDirectories: ['', '.', 'relative-location'],
        ),
        throwsA(isA<SchedulerException>()),
      );
    },
  );

  test(
    'Windows drive-relative and current-drive paths remain nonabsolute',
    () {
      for (final path in [
        r'C:tools',
        r'\tools',
        r'%ProgramFiles%\PowerShell\7',
      ]) {
        expect(Directory(path).isAbsolute, isFalse, reason: path);
      }
    },
    skip: !Platform.isWindows
        ? 'This checks the actual Windows Dart filesystem path implementation.'
        : false,
  );

  test('a pwsh.exe directory is not an executable file', () {
    Directory.fromUri(fixture.uri.resolve('pwsh.exe/'))
        .createSync(recursive: true);
    expect(
      () => resolveWindowsPowerShell(pathDirectories: [fixture.path]),
      throwsA(isA<SchedulerException>()),
    );
  });

  test('missing installation gives the same actionable requirement', () {
    expect(
      () => resolveWindowsPowerShell(pathDirectories: [fixture.path]),
      throwsA(
        isA<SchedulerException>().having(
          (error) => error.message,
          'message',
          contains('add pwsh.exe to PATH'),
        ),
      ),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Platform window integration is isolated from the Flutter UI and worker.
/// Widget tests inject no host; no native window operations run in tests.
abstract class SchedulerWindowHost {
  Future<void> setMode({required bool compact, required bool hasRun});
  Future<void> showDialogWindow({required bool history});
  Future<void> restoreMode({required bool compact, required bool hasRun});
}

class DesktopWindowHost implements SchedulerWindowHost {
  Size _fullSize = const Size(1000, 800);
  bool _lastCompact = false;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1000, 800),
        center: true,
      ),
      () async {
        await windowManager.setMinimumSize(const Size(800, 570));
        await windowManager.setTitle('Codex Resume Scheduler — Flutter review');
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  @override
  Future<void> setMode({required bool compact, required bool hasRun}) async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    if (compact) {
      if (!_lastCompact) _fullSize = await windowManager.getSize();
      await windowManager.setMinimumSize(const Size(475, 395));
      await windowManager.setSize(Size(515, hasRun ? 555 : 370));
    } else {
      await windowManager.setSize(_fullSize);
      await windowManager.setMinimumSize(const Size(800, 570));
    }
    _lastCompact = compact;
  }

  @override
  Future<void> showDialogWindow({required bool history}) async {
    if (!_lastCompact) return;
    // Flutter dialogs live in the same window; expand it temporarily so all
    // appearance and history controls remain accessible in compact mode.
    await windowManager.setMinimumSize(const Size(475, 395));
    await windowManager.setSize(history
      ? const Size(1040, 780)
      : const Size(690, 830));
  }

  @override
  Future<void> restoreMode({required bool compact, required bool hasRun}) async {
    await setMode(compact: compact, hasRun: hasRun);
  }
}

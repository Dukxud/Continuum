import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Platform window integration is isolated from the Flutter UI and worker.
/// Widget tests inject no host; no native window operations run in tests.
abstract class SchedulerWindowHost {
  Future<void> setMode({required bool compact, required bool hasRun,
    required int quotaWindowCount});
  Future<void> showDialogWindow({required bool history});
  Future<void> restoreMode({required bool compact, required bool hasRun,
    required int quotaWindowCount});
}

class DesktopWindowHost implements SchedulerWindowHost {
  Size _fullSize = const Size(952, 610);
  bool _lastCompact = false;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(952, 610),
        center: true,
      ),
      () async {
        await windowManager.setMinimumSize(const Size(940, 590));
        await windowManager.setTitle('Codex Resume Scheduler v1.16.0 — Flutter review');
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  @override
  Future<void> setMode({required bool compact, required bool hasRun,
    required int quotaWindowCount}) async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    if (compact) {
      if (!_lastCompact) _fullSize = await windowManager.getSize();
      final count = quotaWindowCount.clamp(0, 2);
      // Match CodexDashboard.ps1: window chrome adds ~43px to ClientSize.
      final clientHeight = count == 0
        ? (hasRun ? 338 : 166)
        : (hasRun ? 338 : 157) + count * 117;
      await windowManager.setMinimumSize(const Size(480, 195));
      await windowManager.setSize(Size(482, clientHeight.toDouble() + 43));
    } else {
      await windowManager.setSize(_fullSize);
      await windowManager.setMinimumSize(const Size(940, 590));
    }
    _lastCompact = compact;
  }

  @override
  Future<void> showDialogWindow({required bool history}) async {
    if (!_lastCompact) return;
    // Flutter dialogs live in the same window; expand it temporarily so all
    // appearance and history controls remain accessible in compact mode.
    await windowManager.setMinimumSize(const Size(480, 380));
    await windowManager.setSize(history
      ? const Size(1040, 780)
      : const Size(690, 830));
  }

  @override
  Future<void> restoreMode({required bool compact, required bool hasRun,
    required int quotaWindowCount}) async {
    await setMode(compact: compact, hasRun: hasRun,
      quotaWindowCount: quotaWindowCount);
  }
}

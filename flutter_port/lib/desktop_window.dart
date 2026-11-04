import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// A single native window hosts both the scheduler and its modal dialogs.
/// Serialize changes so a late asynchronous resize cannot undo a newer mode.
class WindowActionQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}

/// Window dimensions are derived from actual content, never an old dragged
/// full-mode size. The native frame accounts for the Windows title bar.
Size schedulerWindowSize({required bool compact, required int upcomingRunCount,
  required int quotaWindowCount}) {
  if (compact) {
    final count = quotaWindowCount.clamp(0, 2);
    final hasRun = upcomingRunCount > 0;
    final clientHeight = count == 0
      ? (hasRun ? 338 : 166)
      : (hasRun ? 338 : 157) + count * 117;
    return Size(482, clientHeight.toDouble() + 43);
  }
  final visibleRows = upcomingRunCount.clamp(0, 4);
  final contentHeight = visibleRows == 0
    ? 566.0 : 660.0 + 40.0 * visibleRows;
  return Size(952, math.max(610.0, contentHeight + 44));
}

abstract class SchedulerWindowHost {
  Future<void> setMode({required bool compact, required int upcomingRunCount,
    required int quotaWindowCount});
  Future<void> showDialogWindow({required bool history});
}

class DesktopWindowHost implements SchedulerWindowHost {
  final WindowActionQueue _actions = WindowActionQueue();
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
  Future<void> setMode({required bool compact, required int upcomingRunCount,
    required int quotaWindowCount}) => _actions.enqueue(() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    final size = schedulerWindowSize(compact: compact,
      upcomingRunCount: upcomingRunCount,
      quotaWindowCount: quotaWindowCount);
    await windowManager.setMinimumSize(compact
      ? const Size(480, 195) : const Size(940, 590));
    await windowManager.setSize(size);
    _lastCompact = compact;
  });

  @override
  Future<void> showDialogWindow({required bool history}) =>
    _actions.enqueue(() async {
      if (!_lastCompact) return;
      // Dialogs share the main native window. Expand temporarily, then
      // restore the exact content size through setMode after closing.
      await windowManager.setMinimumSize(const Size(480, 380));
      await windowManager.setSize(history
        ? const Size(1040, 780)
        : const Size(610, 610));
    });
}

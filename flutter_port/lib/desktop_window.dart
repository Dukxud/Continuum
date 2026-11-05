
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
    // An independent live monitor; never a squeezed full workbench.
    return Size(540, upcomingRunCount > 0 ? 685 : 535);
  }
  return const Size(1240, 850);
}

abstract class SchedulerWindowHost {
  Future<void> setMode({required bool compact, required int upcomingRunCount,
    required int quotaWindowCount});
  Future<void> showDialogWindow({required bool history});

  // X/Alt+F4 hides the native window before any pending persistence I/O.
  // The process stays alive only until those settings are safely stored.
  Future<void> hideForShutdown();
  Future<void> restoreAfterFailedShutdown();
  Future<void> finishShutdown();
}

class DesktopWindowHost implements SchedulerWindowHost {
  final WindowActionQueue _actions = WindowActionQueue();
  bool _lastCompact = false;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1240, 850),
        center: true,
      ),
      () async {
        // Intercept native X/Alt+F4 so the controller can flush pending edits.
        await windowManager.setPreventClose(true);
        await windowManager.setMinimumSize(const Size(1100, 750));
        await windowManager.setTitle('Codex Resume Scheduler — Continuum preview');
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
      ? const Size(520, 490) : const Size(1100, 750));
    await windowManager.setSize(size);
    _lastCompact = compact;
  });

  @override
  Future<void> showDialogWindow({required bool history}) =>
    _actions.enqueue(() async {
      if (!_lastCompact) return;
      // Dialogs share the main native window. Expand temporarily, then
      // restore the exact content size through setMode after closing.
      await windowManager.setMinimumSize(const Size(520, 490));
      await windowManager.setSize(history
        ? const Size(1040, 780)
        : const Size(750, 820));
    });

  // Do not queue hiding behind a slow resize; close should look immediate.
  @override
  Future<void> hideForShutdown() => windowManager.hide();

  @override
  Future<void> restoreAfterFailedShutdown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> finishShutdown() => windowManager.destroy();
}

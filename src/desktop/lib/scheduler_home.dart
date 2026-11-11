import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'aero_bar.dart';
import 'appearance_dialog.dart';
import 'desktop_window.dart';
import 'date_labels.dart';
import 'dashboard_skin.dart';
import 'bridge.dart';
import 'scheduler_controller.dart';
import 'live_activity_dialog.dart';
import 'history_dialog.dart';
import 'schedule_time.dart';
import 'windows_scheduler_adapter.dart';

part 'dashboard_frame.dart';
part 'dashboard_workbench.dart';
part 'dashboard_monitor.dart';
part 'dashboard_micro.dart';

class SchedulerHome extends StatefulWidget {
  const SchedulerHome({super.key, this.adapter, this.windowHost});
  final SchedulerAdapter? adapter;
  final SchedulerWindowHost? windowHost;
  @override
  State<SchedulerHome> createState() => _SchedulerHomeState();
}

class _SchedulerHomeState extends State<SchedulerHome> with WindowListener {
  SchedulerController? controller;
  String? startupError;
  final repository = TextEditingController();
  final instruction = TextEditingController();
  bool hydrated = false;
  String? selectedRun;

  // State mutations belong to the State subclass, not its UI-only extension.
  void selectRun(String name) {
    setState(() => selectedRun = name);
  }

  bool _dialogOpen = false;
  bool _closing = false;
  bool _pinRestored = false;
  bool _changingPin = false;
  String _lastWindowKey = '';

  void updateWindowSize() {
    final state = controller;
    final host = widget.windowHost;
    if (state == null || host == null || !state.ready || _dialogOpen) return;
    final quotaCount = math.min(2, state.quotaWindows.length);
    final runCount = state.upcoming.length;
    final key =
        '${state.micro
            ? 'micro'
            : state.compact
            ? 'compact'
            : 'standard'}-runs:${math.min(4, runCount)}-quota:$quotaCount';
    if (_lastWindowKey == key) return;
    _lastWindowKey = key;
    unawaited(
      host
          .setMode(
            compact: state.compact,
            micro: state.micro,
            upcomingRunCount: runCount,
            quotaWindowCount: quotaCount,
          )
          .catchError((Object error) {
            if (mounted) toast('Unable to resize window: $error');
          }),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.windowHost != null) windowManager.addListener(this);
    try {
      controller = SchedulerController(
        widget.adapter ?? WindowsSchedulerAdapter(),
      );
      controller!.addListener(_notify);
      controller!.start();
    } catch (error) {
      startupError = error.toString();
    }
  }

  void _notify() {
    final state = controller;
    if (state == null || !mounted) return;
    if (state.ready && !hydrated) {
      hydrated = true;
      instruction.text = state.message;
    }
    // A refreshed session list can select a different conversation. Keep the
    // visible field paired with the controller's repository, including when
    // the prior checkout must be cleared. TextField.onChanged already updates
    // state.repo before _notify, so ordinary typing does not reset the cursor.
    if (repository.text != state.repo) {
      repository.value = TextEditingValue(
        text: state.repo,
        selection: TextSelection.collapsed(offset: state.repo.length),
      );
    }
    updateWindowSize();
    if (state.ready && !_pinRestored) {
      _pinRestored = true;
      final host = widget.windowHost;
      if (host != null && state.alwaysOnTop) {
        unawaited(
          host.setAlwaysOnTop(true).catchError((Object error) {
            if (!mounted) return;
            // Windows rejected the pin: correct the UI and saved preference.
            if (state.alwaysOnTop) state.edit(pinOnTop: false);
            toast('Unable to restore Always on Top: $error');
          }),
        );
      }
    }
    setState(() {});
  }

  Future<void> toggleAlwaysOnTop() async {
    final state = controller;
    if (state == null || !state.ready || _changingPin) return;
    final desired = !state.alwaysOnTop;
    final host = widget.windowHost;
    if (host == null) {
      toast('Always on Top requires a desktop window.');
      return;
    }
    _changingPin = true;
    try {
      // A successful native operation is required before persisting its
      // visual state. This does not depend on the PowerToys hotkey.
      await host.setAlwaysOnTop(desired);
      if (!mounted) return;
      state.edit(pinOnTop: desired);
    } catch (error) {
      if (mounted) toast('Unable to change Always on Top: $error');
    } finally {
      _changingPin = false;
    }
  }

  @override
  void onWindowFocus() {
    if (!mounted || _dialogOpen) return;
    final state = controller;
    if (state != null) unawaited(state.refreshOnFocus());
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    if (controller?.busy == true) {
      toast('Scheduling or cancellation is still in progress.');
      return;
    }
    _closing = true;
    unawaited(_closeAfterSave());
  }

  Future<void> _closeAfterSave() async {
    final host = widget.windowHost;
    var hidden = false;
    try {
      // Do the visible part of closing first. No disk or PowerShell wait
      // occurs while the operator is still looking at the window.
      if (host != null) {
        await host.hideForShutdown();
        hidden = true;
      }
      final saved = await controller?.flushPreferences() ?? true;
      if (!saved) {
        throw StateError('Preferences could not be saved.');
      }
      if (host != null) {
        await host.finishShutdown();
      } else {
        await windowManager.destroy();
      }
    } catch (error) {
      // Failure must remain recoverable. Never exit with unsaved changes.
      var recoveryError = '';
      if (hidden && host != null) {
        try {
          await host.restoreAfterFailedShutdown();
        } catch (e) {
          recoveryError = ' Window restoration failed: $e';
        }
      }
      _closing = false;
      toast('Unable to close safely: $error$recoveryError');
    }
  }

  @override
  void dispose() {
    if (widget.windowHost != null) windowManager.removeListener(this);
    controller?.removeListener(_notify);
    controller?.dispose();
    repository.dispose();
    instruction.dispose();
    super.dispose();
  }

  void toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<bool> confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String timeLabel(DateTime? time) =>
      time == null ? 'Unavailable' : formatLocalDateTime(time);

  String countdown(DateTime? due) => countdownText(due);

  Future<void> pickDate() async {
    final state = controller!;
    final now = DateTime.now();
    // Keep the Monday-first calendar and day–month ordering.
    final day = await showDatePicker(
      context: context,
      locale: const Locale('en', 'GB'),
      initialDate: state.runAt.isBefore(now) ? now : state.runAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3, 12, 31),
    );
    if (day == null || !mounted) return;
    final selected = state.runAt;
    state.edit(
      time: DateTime(
        day.year,
        day.month,
        day.day,
        selected.hour,
        selected.minute,
        selected.second,
      ),
    );
  }

  Future<void> pickTime() async {
    final state = controller!;
    // The clock portion opens directly in keyboard entry, rather than
    // requiring a calendar and then hiding text input behind a dial.
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(state.runAt),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Enter run time',
    );
    if (time == null || !mounted) return;
    final selected = state.runAt;
    // Only hours/minutes are editable, per the agreed precision scope.
    state.edit(
      time: DateTime(
        selected.year,
        selected.month,
        selected.day,
        time.hour,
        time.minute,
        selected.second,
      ),
    );
  }

  Future<void> schedule() async {
    final state = controller!;
    var unrestricted = false;
    if (state.access == 'yolo') {
      unrestricted = await confirm(
        'Unrestricted access',
        'Commands will run without sandbox or approval prompts.',
      );
      if (!unrestricted || !mounted) return;
    }
    final similar = state.upcoming
        .where(
          (r) =>
              stringField(r, 'Repo').toLowerCase().replaceAll('\\', '/') ==
              state.repo.trim().toLowerCase().replaceAll('\\', '/'),
        )
        .toList();
    if (similar.any(
      (r) =>
          stringField(r, 'Status') == 'Running' &&
          stringField(r, 'Session') == state.sessionId,
    )) {
      toast('This conversation is already running.');
      return;
    }
    var overlap = false;
    if (similar.isNotEmpty) {
      overlap = await confirm(
        'Existing scheduled work',
        'Other runs target this repository. Concurrent work could conflict. Continue?',
      );
      if (!overlap || !mounted) return;
    }
    try {
      final name = await state.schedule(
        confirmUnrestricted: unrestricted,
        confirmOverlap: overlap,
      );
      toast('Scheduled: $name');
    } on SchedulerOutcomeUncertain catch (e) {
      toast(e.toString());
    } catch (e) {
      toast('Scheduling failed: $e');
    }
  }

  Future<void> openRunActivity(String name) async {
    final state = controller;
    if (state == null || _dialogOpen || !mounted) return;
    Map<String, dynamic>? running;
    for (final row in state.upcoming) {
      if (stringField(row, 'Name') == name &&
          stringField(row, 'Status') == 'Running') {
        running = Map<String, dynamic>.of(row);
        break;
      }
    }
    if (running == null) return;
    _dialogOpen = true;
    try {
      // Monitor and Micro share the native window with their dialogs.
      // Expand it temporarily to make the timeline readable.
      await widget.windowHost?.showDialogWindow(history: false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => LiveActivityDialog(controller: state, run: running!),
      );
    } catch (error) {
      if (mounted) toast('Unable to show live activity: $error');
    } finally {
      _dialogOpen = false;
      _lastWindowKey = '';
      updateWindowSize();
    }
  }

  Future<void> historyDialog() async {
    final state = controller;
    if (state == null || _dialogOpen || !mounted) return;
    _dialogOpen = true;
    try {
      await widget.windowHost?.showDialogWindow(history: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => HistoryDialog(
          rows: state.history,
          readEvidence: state.evidence,
          hideRun: state.hide,
        ),
      );
    } catch (error) {
      if (mounted) toast('Unable to show history: $error');
    } finally {
      _dialogOpen = false;
      _lastWindowKey = '';
      updateWindowSize();
    }
  }

  Future<void> appearanceDialog() async {
    final state = controller!;
    _dialogOpen = true;
    try {
      await widget.windowHost?.showDialogWindow(history: false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AeroAppearanceEditor(
          initial: state.appearance,
          onChanged: state.updateAppearance,
        ),
      );
    } catch (error) {
      toast('Appearance editor: $error');
    } finally {
      // Persist the final choice even if the editor closes during debounce.
      await state.flushPreferences();
      _dialogOpen = false;
      _lastWindowKey = '';
      updateWindowSize();
    }
  }

  Future<void> openLogs() async {
    final directory = controller!.logDirectory;
    if (directory.isEmpty) return;
    try {
      await Process.start('explorer.exe', [
        directory,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      toast('Cannot open logs: $e');
    }
  }

  /// Shared controls keep Full, Monitor and Micro navigation consistent.
  Widget viewMenu({bool tight = false}) {
    final state = controller!;
    final selected = state.micro
        ? 'micro'
        : state.compact
        ? 'monitor'
        : 'full';
    return PopupMenuButton<String>(
      key: const Key('view-menu'),
      tooltip: 'View',
      initialValue: selected,
      onSelected: (mode) =>
          state.edit(microMode: mode == 'micro', compactMode: mode != 'full'),
      itemBuilder: (_) => [
        CheckedPopupMenuItem<String>(
          value: 'full',
          checked: selected == 'full',
          child: const Text('Full'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'monitor',
          checked: selected == 'monitor',
          child: const Text('Monitor'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'micro',
          checked: selected == 'micro',
          child: const Text('Micro'),
        ),
      ],
      child: _menuFace(
        Icons.layers_outlined,
        DeckColor.aqua,
        label: tight ? null : 'View',
      ),
    );
  }

  Widget moreMenu() => PopupMenuButton<String>(
    key: const Key('more-menu'),
    tooltip: 'More',
    onSelected: (action) {
      if (action == 'history') unawaited(historyDialog());
      if (action == 'logs') unawaited(openLogs());
      if (action == 'appearance') unawaited(appearanceDialog());
    },
    itemBuilder: (_) => const [
      PopupMenuItem<String>(value: 'history', child: Text('History')),
      PopupMenuItem<String>(value: 'logs', child: Text('Logs')),
      PopupMenuItem<String>(value: 'appearance', child: Text('Appearance')),
    ],
    child: _menuFace(Icons.more_horiz_rounded, DeckColor.iris),
  );

  Widget pinButton() {
    final state = controller!;
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        key: const Key('pin-window'),
        tooltip: state.alwaysOnTop ? 'Unpin window' : 'Always on Top',
        onPressed: state.ready ? toggleAlwaysOnTop : null,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xff27304a),
          side: BorderSide(
            color: (state.alwaysOnTop ? DeckColor.gold : DeckColor.aqua)
                .withValues(alpha: .42),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        icon: Icon(
          state.alwaysOnTop ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          size: 19,
          color: state.alwaysOnTop ? DeckColor.gold : DeckColor.aqua,
        ),
      ),
    );
  }

  Widget _menuFace(IconData glyph, Color tone, {String? label}) => Container(
    width: label == null ? 36 : 96,
    height: 36,
    decoration: BoxDecoration(
      color: const Color(0xff27304a),
      border: Border.all(color: tone.withValues(alpha: .42)),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(glyph, color: tone, size: 19),
        if (label != null) ...[
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: DeckColor.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: DeckColor.muted, size: 15),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = controller;
    if (state == null) {
      return Scaffold(
        body: Center(child: Text(startupError ?? 'Scheduler unavailable')),
      );
    }
    return Scaffold(
      backgroundColor: DeckColor.voidInk,
      body: SafeArea(
        child: state.micro
            ? _microDeck()
            : state.compact
            ? _compactDeck()
            : _fullDeck(),
      ),
    );
  }
}

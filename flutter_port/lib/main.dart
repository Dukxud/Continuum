import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aero_bar.dart';
import 'aero_appearance.dart';
import 'appearance_dialog.dart';
import 'desktop_window.dart';
import 'bridge.dart';
import 'scheduler_controller.dart';

part 'windows_parity_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DesktopWindowHost? host;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    host = DesktopWindowHost();
    await host.initialize();
  }
  runApp(SchedulerApp(windowHost: host));
}

const accent = Color(0xff516f98);
const surface = Color(0xffedf3fa);

class SchedulerApp extends StatelessWidget {
  const SchedulerApp({super.key, this.windowHost});
  final SchedulerWindowHost? windowHost;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Codex Resume Scheduler — Flutter preview',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xfff5f7fb),
      colorScheme: ColorScheme.fromSeed(seedColor: accent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
    ),
    home: SchedulerHome(windowHost: windowHost),
  );
}

class SchedulerHome extends StatefulWidget {
  const SchedulerHome({super.key, this.adapter, this.windowHost});
  final SchedulerAdapter? adapter;
  final SchedulerWindowHost? windowHost;
  @override
  State<SchedulerHome> createState() => _SchedulerHomeState();
}

class _SchedulerHomeState extends State<SchedulerHome> {
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
  String _lastWindowKey = '';

  void updateWindowSize() {
    final state = controller;
    final host = widget.windowHost;
    if (state == null || host == null || !state.ready || _dialogOpen) return;
    final key = (state.compact ? 'compact' : 'standard') +
      (state.upcoming.isEmpty ? '-empty' : '-has-run');
    if (_lastWindowKey == key) return;
    _lastWindowKey = key;
    unawaited(host.setMode(compact: state.compact,
      hasRun: state.upcoming.isNotEmpty).catchError((Object error) {
        if (mounted) toast('Unable to resize window: ' + error.toString());
      }));
  }

  @override
  void initState() {
    super.initState();
    try {
      controller = SchedulerController(widget.adapter ?? WindowsSchedulerAdapter());
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
      repository.text = state.repo;
      instruction.text = state.message;
    } else if (repository.text.isEmpty && state.repo.isNotEmpty) {
      repository.text = state.repo;
    }
    updateWindowSize();
    setState(() {});
  }

  @override
  void dispose() {
    controller?.removeListener(_notify);
    controller?.dispose();
    repository.dispose();
    instruction.dispose();
    super.dispose();
  }

  void toast(String message) {
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> confirm(String title, String message) async {
    return await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title), content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Continue')),
        ])) ?? false;
  }

  String timeLabel(DateTime? time) {
    if (time == null) return 'Unavailable';
    String pad(int n) => n.toString().padLeft(2, '0');
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return time.month.toString() + '/' + pad(time.day) + '  ' +
      hour.toString() + ':' + pad(time.minute) + (time.hour < 12 ? ' AM' : ' PM');
  }

  String countdown(DateTime? due) {
    if (due == null) return 'Unknown';
    final left = due.difference(DateTime.now());
    if (left.isNegative) return 'Due now';
    if (left.inDays > 0) return left.inDays.toString() + 'd ' +
        (left.inHours % 24).toString() + 'h';
    if (left.inHours > 0) return left.inHours.toString() + 'h ' +
        (left.inMinutes % 60).toString() + 'm';
    if (left.inMinutes > 0) return left.inMinutes.toString() + 'm ' +
        (left.inSeconds % 60).toString() + 's';
    return left.inSeconds.toString() + 's';
  }

  Future<void> pickTime() async {
    final state = controller!;
    final now = DateTime.now();
    final day = await showDatePicker(context: context,
      initialDate: state.runAt.isBefore(now) ? now : state.runAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3, 12, 31));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context,
      initialTime: TimeOfDay.fromDateTime(state.runAt));
    if (time == null || !mounted) return;
    state.edit(time: DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> schedule() async {
    final state = controller!;
    var unrestricted = false;
    if (state.access == 'yolo') {
      unrestricted = await confirm('Unrestricted access',
        'Unattended commands will run without sandbox or approval prompts.');
      if (!unrestricted || !mounted) return;
    }
    final similar = state.upcoming.where((r) =>
      stringField(r, 'Repo').toLowerCase().replaceAll('\\', '/') ==
      state.repo.trim().toLowerCase().replaceAll('\\', '/')).toList();
    if (similar.any((r) => stringField(r, 'Status') == 'Running'
        && stringField(r, 'Session') == state.sessionId)) {
      toast('This conversation is already running.'); return;
    }
    var overlap = false;
    if (similar.isNotEmpty) {
      overlap = await confirm('Existing scheduled work',
        'Other runs target this repository. Concurrent work could conflict. Continue?');
      if (!overlap || !mounted) return;
    }
    try {
      final name = await state.schedule(
        confirmUnrestricted: unrestricted, confirmOverlap: overlap);
      toast('Scheduled: $name');
    } catch (e) {
      toast('Scheduling failed: $e');
    }
  }

  Future<void> historyDialog() async {
    final state = controller!;
    final rows = List<Map<String, dynamic>>.of(state.history);
    Map<String, dynamic>? selected;
    String response = '';
    String log = '';
    int generation = 0;
    bool reading = false;
    _dialogOpen = true;
    try {
      await widget.windowHost?.showDialogWindow(history: true);
      if (!mounted) return;
      await showDialog<void>(context: context,
      builder: (parent) => StatefulBuilder(builder: (dialog, refresh) {
        Future<void> select(Map<String, dynamic> row) async {
          final token = ++generation;
          refresh(() { selected = row; reading = true; response = ''; log = ''; });
          try {
            final result = await state.evidence(stringField(row, 'Name'));
            if (!parent.mounted || token != generation) return;
            refresh(() {
              response = stringField(result, 'Response');
              log = stringField(result, 'Transcript');
              reading = false;
            });
          } catch (e) {
            if (!parent.mounted || token != generation) return;
            refresh(() { response = 'Cannot read evidence: $e'; reading = false; });
          }
        }
        Future<void> hide() async {
          if (selected == null) return;
          final name = stringField(selected, 'Name');
          if (!await confirm('Remove from history',
            'Hide this result? Windows jobs, logs and event records remain untouched.')) return;
          try {
            await state.hide(name);
            rows.removeWhere((r) => stringField(r, 'Name') == name);
            if (parent.mounted) refresh(() { selected = null; response = ''; log = ''; });
          } catch (e) { toast('Unable to hide result: $e'); }
        }
        return Dialog(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050, maxHeight: 650),
          child: Padding(padding: const EdgeInsets.all(17),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('Recent Codex runs',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(parent), icon: const Icon(Icons.close)),
              ]),
              const Divider(),
              Expanded(child: LayoutBuilder(builder: (context, constraints) {
                final list = ListView.builder(
                  itemCount: rows.length, itemBuilder: (context, i) {
                    final row = rows[i];
                    final name = stringField(row, 'Name');
                    return ListTile(dense: true,
                      selected: selected != null && stringField(selected, 'Name') == name,
                      title: Text(timeLabel(dateField(row, 'When')) + ' · ' +
                        stringField(row, 'Status')),
                      subtitle: Text(name + '\n' + stringField(row, 'Message'),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => select(row));
                  });
                final detail = DefaultTabController(length: 2, child: Column(children: [
                  if (selected != null) Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    color: surface,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Result: ' + stringField(selected, 'Status') +
                        '  ·  Exit: ' + (field(selected, 'ExitCode')?.toString() ?? '—') +
                        '  ·  Attempt: ' + (field(selected, 'Attempt')?.toString() ?? '—'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      if (stringField(selected, 'NextJob').isNotEmpty)
                        Text('Next task: ' + stringField(selected, 'NextJob'),
                          style: const TextStyle(fontSize: 12)),
                      if (stringField(selected, 'Message').isNotEmpty)
                        Text(stringField(selected, 'Message'),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  if (reading) const LinearProgressIndicator(),
                  const TabBar(tabs: [Tab(text: 'Codex response'), Tab(text: 'Worker log')]),
                  Expanded(child: TabBarView(children: [
                    SingleChildScrollView(padding: const EdgeInsets.all(12),
                      child: SelectableText(response.isEmpty ? 'Select a run to inspect its response.' : response)),
                    SingleChildScrollView(padding: const EdgeInsets.all(12),
                      child: SelectableText(log.isEmpty ? 'Select a run to inspect its worker log.' : log)),
                  ])),
                ]));
                if (constraints.maxWidth < 650) {
                  return Column(children: [
                    SizedBox(height: math.min(180, constraints.maxHeight * 0.37), child: list),
                    const Divider(),
                    Expanded(child: detail),
                  ]);
                }
                return Row(children: [
                  SizedBox(width: math.min(335, constraints.maxWidth * 0.36), child: list),
                  const VerticalDivider(),
                  Expanded(child: detail),
                ]);
              })),
              const Divider(),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(onPressed: response.isEmpty ? null :
                  () => Clipboard.setData(ClipboardData(text: response)),
                  icon: const Icon(Icons.copy, size: 17), label: const Text('Copy response')),
                OutlinedButton.icon(onPressed: log.isEmpty ? null :
                  () => Clipboard.setData(ClipboardData(text: log)),
                  icon: const Icon(Icons.copy, size: 17), label: const Text('Copy worker log')),
                OutlinedButton.icon(onPressed: selected == null ? null : hide,
                  icon: const Icon(Icons.remove_circle_outline, size: 17),
                  label: const Text('Remove from history')),
              ]),
            ]))));
      }));
    } finally {
      _dialogOpen = false;
      _lastWindowKey = '';
      updateWindowSize();
    }
  }

  Future<void> appearanceDialog() async {
    final state = controller!;
    state.beginAppearancePreview();
    _dialogOpen = true;
    try {
      await widget.windowHost?.showDialogWindow(history: false);
      if (!mounted) {
        state.cancelAppearancePreview();
        return;
      }
      final chosen = await showDialog<AeroAppearance>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AeroAppearanceEditor(
          initial: state.appearance,
          onPreview: state.previewAppearance,
        ),
      );
      if (chosen == null) {
        state.cancelAppearancePreview();
      } else {
        state.commitAppearance(chosen);
      }
    } catch (error) {
      state.cancelAppearancePreview();
      toast('Appearance editor: ' + error.toString());
    } finally {
      _dialogOpen = false;
      _lastWindowKey = '';
      updateWindowSize();
    }
  }

  Future<void> openLogs() async {
    final directory = controller!.logDirectory;
    if (directory.isEmpty) return;
    try {
      await Process.start('explorer.exe', [directory],
        mode: ProcessStartMode.detached);
    } catch (e) { toast('Cannot open logs: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final state = controller;
    if (state == null) {
      return Scaffold(body:Center(child:Text(startupError ?? 'Scheduler unavailable')));
    }
    return Scaffold(
      backgroundColor:const Color(0xfff0f5fb),
      body:SafeArea(child:state.compact?_compactParityView():_fullParityView()),
    );
  }
}

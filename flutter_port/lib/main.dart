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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DesktopWindowHost? host;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    host = DesktopWindowHost();
    await host.initialize();
  }
  runApp(SchedulerApp(windowHost: host));
}

const ink = Color(0xff21334b);
const slate = Color(0xff60718a);
const accent = Color(0xff516f98);
const primary = Color(0xff2277a1);
const surface = Color(0xffedf3fa);
const edge = Color(0xffc9d7e9);

class SchedulerApp extends StatelessWidget {
  const SchedulerApp({super.key, this.windowHost});
  final SchedulerWindowHost? windowHost;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Codex Resume Scheduler — Flutter preview',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff5f7fb),
      colorScheme: ColorScheme.fromSeed(seedColor: accent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
      cardTheme: CardThemeData(
        color: Colors.white, elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9), side: const BorderSide(color: edge))),
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

  Widget section(String title, Widget content) => Card(
    margin: const EdgeInsets.only(bottom: 13),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: ink, fontWeight: FontWeight.w800,
          fontSize: 15)),
        const SizedBox(height: 11),
        content,
      ]),
    ),
  );

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

  Widget editing() {
    final state = controller!;
    final validSessions = state.sessions.where(
      (s) => stringField(s, 'Id') == state.sessionId).isNotEmpty;
    final validModels = state.models.where(
      (m) => stringField(m, 'id') == state.model).isNotEmpty;
    final efforts = state.efforts;
    final resetEpoch = field(state.quota, 'recommendedResetAt');
    final reset = stringField(state.quota, 'recommendationKind') == 'exhausted-window'
        && resetEpoch is num && resetEpoch > 0
      ? nextWholeMinute(DateTime.fromMillisecondsSinceEpoch(
          resetEpoch.toInt() * 1000).add(const Duration(minutes: 2)))
      : null;
    return Column(children: [
      section('CONVERSATION', DropdownButtonFormField<String>(
        value: validSessions ? state.sessionId : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Saved CLI conversation'),
        hint: const Text('Select conversation'),
        items: state.sessions.map((session) => DropdownMenuItem(
          value: stringField(session, 'Id'),
          child: Text(stringField(session, 'Display'), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (id) { repository.clear(); state.selectSession(id); })),
      section('REPOSITORY', Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(
            controller: repository,
            onChanged: (v) => state.edit(repository: v),
            decoration: const InputDecoration(labelText: 'Git repository path'))),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: () async {
            try {
              final result = await state.adapter.call('browse');
              final folder = stringField(result, 'path');
              if (folder.isNotEmpty) {
                repository.text = folder;
                state.edit(repository: folder);
              }
            } catch (e) { toast('Folder picker: $e'); }
          }, child: const Text('Browse...')),
        ]),
        if (state.repositoryWarning != null) ...[
          const SizedBox(height: 6),
          Text(state.repositoryWarning!,
            style: const TextStyle(color: Colors.deepOrange, fontSize: 12)),
          for (final root in state.repositoryAlternatives)
            TextButton(
              onPressed: () {
                repository.text = root;
                state.edit(repository: root);
              },
              child: Text('Use ' + root, overflow: TextOverflow.ellipsis)),
        ],
      ])),
      section('RUN AT', Wrap(spacing: 9, runSpacing: 9,
        crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton(onPressed: () => state.edit(time: stepRunAt(state.runAt, -1)),
          child: const Text('−')),
        OutlinedButton(onPressed: pickTime,
          child: Text(timeLabel(state.runAt),
            style: const TextStyle(fontWeight: FontWeight.w700))),
        OutlinedButton(onPressed: () => state.edit(time: stepRunAt(state.runAt, 1)),
          child: const Text('+')),
        OutlinedButton(onPressed: () => state.edit(time: suggestedRunAt()),
          child: const Text('Now +2')),
        OutlinedButton(onPressed: reset == null ? null : () => state.edit(time: reset),
          child: const Text('Reset +2')),
      ])),
      section('OPTIONS', LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth >= 690
          ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth;
        return Wrap(spacing: 12, runSpacing: 10, children: [
          SizedBox(width: width, child: DropdownButtonFormField<String>(
            isExpanded: true, value: validModels ? state.model : null,
            decoration: const InputDecoration(labelText: 'Model'),
            items: state.models.map((m) => DropdownMenuItem(
              value: stringField(m, 'id'),
              child: Text(stringField(m, 'name').isEmpty ? stringField(m, 'id') :
                stringField(m, 'name'), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: state.selectModel)),
          SizedBox(width: width, child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: efforts.contains(state.effort) ? state.effort : null,
            decoration: const InputDecoration(labelText: 'Reasoning'),
            items: efforts.map((e) => DropdownMenuItem(value: e,
              child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (value) { if (value != null) state.edit(reasoning: value); })),
          SizedBox(width: width, child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: state.access,
            decoration: const InputDecoration(labelText: 'Access'),
            items: const [
              DropdownMenuItem(value: 'workspace-write', child: Text('Workspace write',
                overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'read-only', child: Text('Read-only',
                overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'yolo', child: Text('Unrestricted',
                overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) { if (value != null) state.edit(accessMode: value); })),
        ]);
      })),
      section('INSTRUCTION', Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        TextField(controller: instruction, minLines: 2, maxLines: 3,
          onChanged: (value) => state.edit(instruction: value),
          decoration: const InputDecoration(hintText: 'What should Codex do?')),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: state.canSchedule ? schedule : null,
          icon: const Icon(Icons.schedule),
          label: Text(state.busy ? 'Working...' : 'Schedule once'),
          style: FilledButton.styleFrom(backgroundColor: primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17))),
        if (!state.canSchedule)
          const Padding(padding: EdgeInsets.only(top: 8),
            child: Text('Requires fresh quota and verified workspace identity',
              style: TextStyle(fontSize: 11, color: slate))),
      ])),
    ]);
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

  Widget quotaCard(Map<String, dynamic>? window, String fallback, String kind) {
    final state = controller!;
    final raw = field(window, 'remainingPercent');
    final remaining = raw is num ? raw.toDouble() : null;
    final epoch = field(window, 'resetsAt');
    final reset = epoch is num && epoch > 0
      ? DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000) : null;
    final title = stringField(window, 'label').isEmpty ? fallback :
      stringField(window, 'label');
    return Container(padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: surface, border: Border.all(color: edge),
        borderRadius: BorderRadius.circular(7)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, color: ink))),
          const SizedBox(width: 8),
          Flexible(child: Text(remaining == null ? 'Unavailable' :
              remaining.toStringAsFixed(1) + '% remaining',
            overflow: TextOverflow.ellipsis, textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700, color: ink))),
        ]),
        const SizedBox(height: 12),
        AeroLiquidBar(amount: remaining, appearance: state.appearance, kind: kind),
        const SizedBox(height: 10),
        Text(reset == null ? 'Reset time unavailable' : 'Resets ' + timeLabel(reset),
          style: const TextStyle(color: slate, fontSize: 12)),
      ]));
  }

  Widget quotas() {
    final windows = recordList(field(controller!.quota, 'windows'));
    final first = quotaCard(windows.isNotEmpty ? windows[0] : null, 'Primary window', 'quota');
    final second = quotaCard(windows.length > 1 ? windows[1] : null, 'Secondary window', 'weekly');
    return LayoutBuilder(builder: (context, constraints) => constraints.maxWidth < 590
      ? Column(children: [first, const SizedBox(height: 10), second])
      : Row(children: [
          Expanded(child: first), const SizedBox(width: 12), Expanded(child: second)]));
  }

  Widget runCountdown(Map<String, dynamic> run) {
    final status = stringField(run, 'Status');
    final working = status == 'Running';
    final due = dateField(run, 'When');
    final createdRaw = field(run, 'CreatedAt');
    double? pct;
    if (!working && due != null && createdRaw is num) {
      final created = DateTime.fromMillisecondsSinceEpoch(createdRaw.toInt() * 1000);
      final total = due.difference(created).inMilliseconds;
      if (total > 0) {
        pct = (DateTime.now().difference(created).inMilliseconds / total * 100)
          .clamp(0.0, 100.0);
      }
    }
    return Row(children: [
      SizedBox(width: 74, child: Text(working ? 'Running' : countdown(due),
        style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700))),
      const SizedBox(width: 5),
      Expanded(child: AeroLiquidBar(amount: pct, working: working,
        kind: working ? 'working' : 'time', appearance: controller!.appearance)),
    ]);
  }

  Widget runItem(Map<String, dynamic> run, {bool compact = false}) {
    final name = stringField(run, 'Name');
    final path = stringField(run, 'Repo');
    final segments = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    final project = segments.isEmpty ? 'Unknown project' : segments.last;
    final date = dateField(run, 'When');
    if (compact) {
      return InkWell(
        onTap: () => setState(() => selectedRun = selectedRun == name ? null : name),
        child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selectedRun == name ? const Color(0xffdbe9f8) : surface,
            border: Border.all(color: edge),
            borderRadius: BorderRadius.circular(7)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(project, style: const TextStyle(color: ink, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(stringField(run, 'Description'), maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(color: slate)),
            Text(timeLabel(date), style: const TextStyle(color: slate, fontSize: 12)),
            const SizedBox(height: 12),
            runCountdown(run),
          ])));
    }
    return InkWell(onTap: () => setState(() => selectedRun = selectedRun == name ? null : name),
      child: Container(color: selectedRun == name ? const Color(0xffdbe9f8) : null,
        height: 58, padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(children: [
          SizedBox(width: 140, child: Text(timeLabel(date),
            style: const TextStyle(fontSize: 12, color: ink))),
          SizedBox(width: 205, child: runCountdown(run)),
          const SizedBox(width: 12),
          SizedBox(width: 130, child: Text(project, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          Expanded(child: Text(stringField(run, 'Description'),
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: slate))),
          SizedBox(width: 68, child: Text(stringField(run, 'Session').length >= 8
            ? stringField(run, 'Session').substring(0, 8) : '—',
            style: const TextStyle(fontSize: 12, color: slate))),
        ])));
  }

  Widget runsGrid() {
    final state = controller!;
    final runs = state.upcoming;
    if (runs.isEmpty) return const SizedBox.shrink();
    return section('UPCOMING RUNS (' + runs.length.toString() + ')',
      LayoutBuilder(builder: (context, constraints) => Column(children: [
        if (constraints.maxWidth < 850) ...[
          for (final run in runs) ...[
            runItem(run, compact: true),
            const SizedBox(height: 7),
          ],
        ] else ...[
        const Row(children: [
          SizedBox(width: 140, child: Text('SCHEDULED', style: TextStyle(fontSize: 10, color: slate))),
          SizedBox(width: 217, child: Text('TIME TO RUN', style: TextStyle(fontSize: 10, color: slate))),
          SizedBox(width: 140, child: Text('PROJECT', style: TextStyle(fontSize: 10, color: slate))),
          Expanded(child: Text('DETAILS', style: TextStyle(fontSize: 10, color: slate))),
          SizedBox(width: 68, child: Text('SESSION', style: TextStyle(fontSize: 10, color: slate))),
        ]),
        const Divider(),
        SizedBox(height: math.min(4, runs.length) * 58.0,
          child: Scrollbar(child: ListView.builder(itemCount: runs.length, itemExtent: 58,
            itemBuilder: (context, index) => runItem(runs[index])))),
        ],
        const Divider(),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
          onPressed: selectedRun == null || state.busy ? null : () async {
            final matches = runs.where((r) => stringField(r, 'Name') == selectedRun &&
              stringField(r, 'Status') == 'Scheduled');
            if (matches.isEmpty) { toast('Only future scheduled runs can be cancelled.'); return; }
            if (!await confirm('Cancel selected', 'Cancel this task in Windows Task Scheduler?')) return;
            try {
              final result = await state.cancel(selectedRun!);
              selectedRun = null;
              if (stringField(result, 'warning').isNotEmpty) {
                toast('Cancelled; cleanup warning: ' + stringField(result, 'warning'));
              }
            } catch (e) { toast('Cancellation failed: $e'); }
          },
          icon: const Icon(Icons.close, size: 17), label: const Text('Cancel selected'))),
      ])));
  }

  Future<void> historyDialog() async {
    final state = controller!;
    final rows = List<Map<String, dynamic>>.of(state.history);
    Map<String, dynamic>? selected;
    String response = '';
    String log = '';
    int generation = 0;
    bool reading = false;
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
                      title: Text(stringField(row, 'Status')),
                      subtitle: Text(timeLabel(dateField(row, 'When')) + '\n' + name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => select(row));
                  });
                final detail = DefaultTabController(length: 2, child: Column(children: [
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
  }

  Future<void> appearanceDialog() async {
    final state = controller!;
    final draft = Map<String, int>.from(state.appearance);
    final swatches = <int>[0xff5baf92, 0xff467dc0, 0xff518d9f,
      0xffba8fcb, 0xffdb9a46, 0xffbe6b7f];
    final saved = await showDialog<bool>(context: context,
      builder: (parent) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('Aero Liquid appearance'),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 470),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final name in ['quota', 'time', 'working']) ...[
            Align(alignment: Alignment.centerLeft, child: Text(
              name == 'quota' ? 'Usage' : name == 'time' ? 'Countdown' : 'Running',
              style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(height: 6),
            AeroLiquidBar(amount: name == 'working' ? null : 76,
              working: name == 'working', tint: Color(draft[name]!)),
            Wrap(spacing: 5, children: [
              for (final value in swatches)
                IconButton(onPressed: () => refresh(() => draft[name] = value),
                  icon: Icon(value == draft[name] ? Icons.check_circle : Icons.circle,
                    color: Color(value))),
            ]),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(parent, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(parent, true),
            child: const Text('Save and close')),
        ],
      )));
    if (saved == true) state.setAppearance(draft);
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
    if (controller == null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(30),
        child: Text(startupError ?? 'Platform adapter unavailable'))));
    }
    final state = controller!;
    return Scaffold(body: SafeArea(child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1110),
      child: SingleChildScrollView(padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            final heading = Row(children: [
              const Icon(Icons.window, color: accent, size: 28),
              const SizedBox(width: 10),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('CODEX RESUME SCHEDULER',
                  style: TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 21, color: ink)),
                Text('Flutter review · Windows bridge to tested v1.16 worker',
                  style: TextStyle(fontSize: 11, color: slate)),
              ])),
            ]);
            final controls = [
              OutlinedButton(onPressed: appearanceDialog,
                child: const Text('Appearance...')),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(state.compact ? 'Compact ON' : 'Compact OFF',
                  style: const TextStyle(color: slate, fontSize: 12)),
                Switch(value: state.compact,
                  onChanged: (v) => state.edit(compactMode: v)),
              ]),
            ];
            return constraints.maxWidth < 700
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  heading, const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 6, children: controls),
                ])
              : Row(children: [
                  Expanded(child: heading), const SizedBox(width: 12),
                  controls.first, const SizedBox(width: 12), controls.last,
                ]);
          }),
          const SizedBox(height: 16),
          if (state.error != null)
            Container(margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xffffe9e3),
                borderRadius: BorderRadius.circular(6)),
              child: Text(state.error!, style: const TextStyle(color: Color(0xff933e2f)))),
          if (!state.compact) editing(),
          if (state.compact && state.upcoming.isNotEmpty)
            section('NEXT RUN', runItem(state.upcoming.first, compact: true)),
          section(state.compact && state.quotaModel.isNotEmpty
            ? 'USAGE REMAINING · ' + state.quotaModel
            : 'USAGE REMAINING', quotas()),
          if (!state.compact && state.upcoming.isNotEmpty) runsGrid(),
          Wrap(spacing: 10, children: [
            OutlinedButton.icon(onPressed: openLogs,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Open logs folder')),
            OutlinedButton.icon(onPressed: historyDialog,
              icon: const Icon(Icons.history, size: 18),
              label: const Text('Recent runs')),
          ]),
        ])),
    ))));
  }
}

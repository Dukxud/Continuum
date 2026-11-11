import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import 'date_labels.dart';

/// A history view with explicit read and hide operations. It does not own
/// scheduling, window state, polling, or process transport.
class HistoryDialog extends StatefulWidget {
  const HistoryDialog({
    super.key,
    required this.rows,
    required this.readEvidence,
    required this.hideRun,
  });

  final List<Map<String, dynamic>> rows;
  final Future<Map<String, dynamic>> Function(String name) readEvidence;
  final Future<void> Function(String name) hideRun;

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  late final List<Map<String, dynamic>> rows = List.of(widget.rows);
  Map<String, dynamic>? selected;
  String response = '';
  String log = '';
  int generation = 0;
  bool reading = false;
  bool removing = false;

  String timeLabel(DateTime? time) =>
      time == null ? 'Unavailable' : formatLocalDateTime(time);

  Future<void> _select(Map<String, dynamic> row) async {
    final token = ++generation;
    setState(() {
      selected = row;
      reading = true;
      response = '';
      log = '';
    });
    try {
      final result = await widget.readEvidence(stringField(row, 'Name'));
      if (!mounted || token != generation) return;
      setState(() {
        response = stringField(result, 'Response');
        log = stringField(result, 'Transcript');
        reading = false;
      });
    } catch (error) {
      if (!mounted || token != generation) return;
      setState(() {
        response = 'Cannot read evidence: $error';
        reading = false;
      });
    }
  }

  Future<void> _hide() async {
    if (selected == null || removing) return;
    final name = stringField(selected, 'Name');
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Remove from history'),
            content: const Text(
              'Hide this result? Windows jobs, logs and event records remain untouched.',
            ),
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
    if (!mounted || !confirmed) return;
    setState(() => removing = true);
    try {
      await widget.hideRun(name);
      if (!mounted) return;
      setState(() {
        rows.removeWhere((row) => stringField(row, 'Name') == name);
        // A pending evidence read must not restore a removed selection.
        // Preserve a different selection made while hideRun was awaiting I/O.
        if (stringField(selected, 'Name') == name) {
          generation++;
          selected = null;
          response = '';
          log = '';
          reading = false;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to hide result: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recent Codex runs',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final list = ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        final name = stringField(row, 'Name');
                        return ListTile(
                          dense: true,
                          selected:
                              selected != null &&
                              stringField(selected, 'Name') == name,
                          title: Text(
                            '${timeLabel(dateField(row, 'When'))} · ${stringField(row, 'Status')}',
                          ),
                          subtitle: Text(
                            '$name\n${stringField(row, 'Message')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _select(row),
                        );
                      },
                    );
                    final detail = DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          if (selected != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(9),
                              color: const Color(0xff26304a),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Result: ${stringField(selected, 'Status')}  ·  Exit: ${field(selected, 'ExitCode')?.toString() ?? '—'}  ·  Attempt: ${field(selected, 'Attempt')?.toString() ?? '—'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (stringField(
                                    selected,
                                    'NextJob',
                                  ).isNotEmpty)
                                    Text(
                                      'Next task: ${stringField(selected, 'NextJob')}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (stringField(
                                    selected,
                                    'Message',
                                  ).isNotEmpty)
                                    Text(
                                      stringField(selected, 'Message'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                          if (reading) const LinearProgressIndicator(),
                          const TabBar(
                            tabs: [
                              Tab(text: 'Codex response'),
                              Tab(text: 'Worker log'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(
                                    response.isEmpty
                                        ? 'Select a run to inspect its response.'
                                        : response,
                                  ),
                                ),
                                SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(
                                    log.isEmpty
                                        ? 'Select a run to inspect its worker log.'
                                        : log,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    if (constraints.maxWidth < 650) {
                      return Column(
                        children: [
                          SizedBox(
                            height: math.min(180, constraints.maxHeight * 0.37),
                            child: list,
                          ),
                          const Divider(),
                          Expanded(child: detail),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: math.min(335, constraints.maxWidth * 0.36),
                          child: list,
                        ),
                        const VerticalDivider(),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
              ),
              const Divider(),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: response.isEmpty
                        ? null
                        : () =>
                              Clipboard.setData(ClipboardData(text: response)),
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('Copy response'),
                  ),
                  OutlinedButton.icon(
                    onPressed: log.isEmpty
                        ? null
                        : () => Clipboard.setData(ClipboardData(text: log)),
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('Copy worker log'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selected == null || removing ? null : _hide,
                    icon: const Icon(Icons.remove_circle_outline, size: 17),
                    label: const Text('Remove from history'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

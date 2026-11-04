part of 'main.dart';

/// Quotas and queued work have their own visual language and actions.
extension _DashboardMonitor on _SchedulerHomeState {
  Widget _monitorColumn(SchedulerController state) {
    final windows = state.quotaWindows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const DeckBeacon(color: DeckColor.mint),
        const SizedBox(width: 5),
        const Expanded(child: Text('CAPACITY / LIVE',
          style: TextStyle(color: DeckColor.muted, fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 1.8))),
        if (state.readingUsage)
          const SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2,
              color: DeckColor.aqua)),
      ]),
      const SizedBox(height: 12),
      SizedBox(height: 133, child: _capacityCard(
        window: windows.isNotEmpty ? windows[0] : null,
        label: 'Five-hour', kind: 'quota',
        accent: DeckColor.mint,
        top: const Color(0xff17443f),
        bottom: const Color(0xff172a3a),
        error: state.error,
      )),
      const SizedBox(height: 13),
      SizedBox(height: 133, child: _capacityCard(
        window: windows.length > 1 ? windows[1] : null,
        label: 'Weekly', kind: 'weekly',
        accent: DeckColor.iris,
        top: const Color(0xff382956),
        bottom: const Color(0xff242440),
        error: state.error,
      )),
      const SizedBox(height: 17),
      Expanded(child: _queueCard(state)),
    ]);
  }

  Widget _capacityCard({
    required Map<String, dynamic>? window,
    required String label,
    required String kind,
    required Color accent,
    required Color top,
    required Color bottom,
    required String? error,
  }) {
    final raw = field(window, 'remainingPercent');
    final remaining = raw is num ? raw.toDouble() : null;
    final resetRaw = field(window, 'resetsAt');
    final reset = resetRaw is num && resetRaw > 0
      ? DateTime.fromMillisecondsSinceEpoch(resetRaw.toInt() * 1000) : null;
    final title = stringField(window, 'label').isNotEmpty
      ? stringField(window, 'label') : label;
    final note = window == null && error?.startsWith('Usage unavailable:') == true
      ? 'Usage unavailable · automatic retry'
      : reset == null ? 'Reset time unavailable'
      : 'Resets ' + formatLocalDateTime(reset);
    return DeckSurface(
      top: top, bottom: bottom, accent: accent,
      radius: 19,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text(title.toUpperCase(),
            style: TextStyle(color: accent, fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: 1.35))),
          Text(remaining == null ? '—' : remaining.toStringAsFixed(1) + '%',
            style: const TextStyle(fontWeight: FontWeight.w900,
              color: DeckColor.text, fontSize: 34, height: 1)),
        ]),
        const SizedBox(height: 3),
        const Text('REMAINING',
          style: TextStyle(color: DeckColor.muted, fontSize: 9,
            letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const Spacer(),
        AeroLiquidBar(amount: remaining, appearance: controller!.appearance,
          kind: kind, height: 16),
        const SizedBox(height: 9),
        Text(note, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: DeckColor.muted,
            fontSize: 10.8)),
      ]),
    );
  }

  Widget _queueCard(SchedulerController state) {
    final runs = state.upcoming;
    final canCancel = !state.busy && runs.any((run) =>
      stringField(run, 'Name') == selectedRun &&
      stringField(run, 'Status') == 'Scheduled');
    return DeckSurface(
      top: const Color(0xff23273e),
      bottom: const Color(0xff171c2e),
      accent: DeckColor.iris,
      padding: const EdgeInsets.all(17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.orbit_rounded,
            color: DeckColor.iris, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('IN FLIGHT',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
              letterSpacing: 1.7, color: DeckColor.text))),
          DeckInfo(runs.length.toString() + ' ACTIVE',
            color: DeckColor.iris),
        ]),
        const SizedBox(height: 12),
        Expanded(child: runs.isEmpty
          ? _emptyQueue()
          : ListView.separated(
              key: const PageStorageKey<String>('upcoming-run-list'),
              padding: EdgeInsets.zero,
              itemCount: runs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) => _runTile(runs[index]),
            )),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(
            runs.isEmpty ? 'All clear.' : 'Select a scheduled run to cancel.',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DeckColor.muted, fontSize: 10))),
          const SizedBox(width: 8),
          DeckAction(label: 'Cancel selected', compact: true,
            tone: DeckColor.rose,
            onTap: canCancel ? cancelSelected : null),
        ]),
      ]),
    );
  }

  Widget _emptyQueue() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.nights_stay_outlined,
        color: DeckColor.iris, size: 38),
      const SizedBox(height: 8),
      const Text('No continuations in flight',
        textAlign: TextAlign.center,
        style: TextStyle(color: DeckColor.text,
          fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      const Text('Your next launch will appear here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: DeckColor.muted, fontSize: 11)),
    ]),
  );

  Widget _runTile(Map<String, dynamic> run) {
    final running = stringField(run, 'Status') == 'Running';
    final when = dateField(run, 'When');
    final name = stringField(run, 'Name');
    final chosen = name == selectedRun;
    final project = stringField(run, 'Repo')
      .split(RegExp(r'[\\/]')).last;
    final tone = running ? DeckColor.gold : DeckColor.aqua;
    final percent = running ? null :
      runElapsedPercent(when, field(run, 'CreatedAt'))?.toDouble();
    return Material(color: Colors.transparent, child: InkWell(
      onTap: () => selectRun(name),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: chosen ? tone.withValues(alpha: .17)
            : const Color(0xff11172a).withValues(alpha: .83),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: chosen
            ? tone.withValues(alpha: .7)
            : DeckColor.line.withValues(alpha: .65)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 5, height: 20,
              decoration: BoxDecoration(color: tone,
                borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 9),
            Expanded(child: Text(project.isEmpty ? 'Unknown repository' : project,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DeckColor.text,
                fontSize: 12.5, fontWeight: FontWeight.w800))),
            Text(running ? 'RUNNING' : countdown(when),
              style: TextStyle(color: tone, fontSize: 11,
                fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 5),
          Text(stringField(run, 'Description'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: DeckColor.muted, fontSize: 10.5)),
          const SizedBox(height: 8),
          AeroLiquidBar(amount: percent, working: running,
            kind: running ? 'working' : 'time',
            appearance: controller!.appearance, height: 11),
          const SizedBox(height: 5),
          Text(when == null ? 'Time unavailable'
              : formatLocalDateTime(when, seconds: true),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DeckColor.subtle, fontSize: 10)),
        ]),
      ),
    ));
  }

  Future<void> cancelSelected() async {
    final state = controller!;
    final matches = state.upcoming.where((run) =>
      stringField(run, 'Name') == selectedRun &&
      stringField(run, 'Status') == 'Scheduled');
    if (matches.isEmpty) {
      toast('Select a future scheduled run.');
      return;
    }
    // The user's selection is explicit intent; the verified Windows worker
    // still independently refuses to cancel a task that has begun.
    try {
      final result = await state.cancel(selectedRun!);
      selectedRun = null;
      final warning = stringField(result, 'warning');
      if (warning.isNotEmpty) toast('Cancelled with warning: ' + warning);
    } on SchedulerOutcomeUncertain catch (error) {
      toast(error.toString());
    } catch (error) {
      toast('Cancellation failed: ' + error.toString());
    }
  }
}

part of 'main.dart';

/// A deliberately small, always-readable instrument. It is not a scaled-down
/// form: micro mode never exposes unsafe scheduling or cancellation actions.
extension _DashboardMicro on _SchedulerHomeState {
  Widget _microDeck() {
    final state = controller!;
    final windows = state.quotaWindows;
    final running = state.upcoming.where(
      (run) => stringField(run, 'Status') == 'Running').toList();
    final next = state.upcoming;
    final activity = running.isNotEmpty
      ? state.activities[stringField(running.first, 'Name')] : null;
    final activityLabel = stringField(activity, 'Summary');
    final status = running.isNotEmpty
      ? 'RUNNING · ${activityLabel.isNotEmpty ? activityLabel : 'Waiting for Codex events'}'
      : next.isNotEmpty
      ? 'NEXT · ${countdown(dateField(next.first, 'When'))}'
      : 'NO RUNS IN FLIGHT';
    return DeckAtmosphere(child: Padding(
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(width: 30, height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [DeckColor.coral, DeckColor.iris])),
              child: const Icon(Icons.play_circle_fill_rounded,
                color: DeckColor.voidInk, size: 19)),
            const SizedBox(width: 8),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
                Text('CONTINUUM', style: TextStyle(
                  color: DeckColor.muted, letterSpacing: 1.4,
                  fontSize: 9, fontWeight: FontWeight.w800)),
                Text('Micro monitor', style: TextStyle(
                  color: DeckColor.text, fontSize: 16,
                  fontWeight: FontWeight.w800)),
              ])),
            viewMenu(),
            const SizedBox(width: 8),
            pinButton(),
            const SizedBox(width: 8),
            moreMenu(),
            const SizedBox(width: 13),
          ]),
          const SizedBox(height: 10),
          DeckSurface(
            top: const Color(0xff172d38),
            bottom: const Color(0xff24213d),
            radius: 12, accent: DeckColor.aqua,
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(children: [
              _microCapacity('5-HOUR', windows.isNotEmpty ? windows[0] : null,
                'quota', DeckColor.mint, state),
              const SizedBox(height: 10),
              _microCapacity('WEEKLY', windows.length > 1 ? windows[1] : null,
                'weekly', DeckColor.iris, state),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            DeckBeacon(color: running.isNotEmpty
              ? DeckColor.gold : DeckColor.aqua),
            const SizedBox(width: 8),
            Expanded(child: Text(status,
              key: const Key('micro-run-status'),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DeckColor.text, fontSize: 10.5,
                fontWeight: FontWeight.w700))),
          ]),
        ],
      ),
    ));
  }

  Widget _microCapacity(String label, Map<String, dynamic>? window,
      String kind, Color accent, SchedulerController state) {
    final value = field(window, 'remainingPercent');
    final remaining = value is num && value.isFinite
      ? value.toDouble() : null;
    final resetAt = dateField(window, 'resetsAt');
    final now = DateTime.now();
    final due = resetAt != null && resetAt.isAfter(now);
    final exhausted = remaining != null && remaining <= 0;
    final resetTime = resetAt == null
      ? 'RESET TIME UNAVAILABLE'
      : due ? 'RESETS ${formatDayMonth(resetAt)} · ${formatLocalClock(resetAt)}'
        : 'RESET DUE · AWAITING UPDATE';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SizedBox(width: 56, child: Text(label, maxLines: 1,
          style: TextStyle(color: accent, fontSize: 9.5,
            fontWeight: FontWeight.w800, letterSpacing: .5))),
        const SizedBox(width: 7),
        Expanded(child: exhausted
          ? Container(
              key: Key('micro-reset-$kind'), height: 19,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: DeckColor.gold.withValues(alpha: .13),
                border: Border.all(
                  color: DeckColor.gold.withValues(alpha: .45))),
              child: Text(due
                ? 'RESET IN ${countdown(resetAt)}'
                : resetAt == null ? 'RESET UNKNOWN' : 'RESET DUE',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DeckColor.gold,
                  fontSize: 10.5, fontWeight: FontWeight.w800)))
          : AeroLiquidBar(
              key: Key('micro-bar-$kind'),
              amount: remaining, appearance: state.appearance,
              kind: kind, height: 12)),
        const SizedBox(width: 9),
        SizedBox(width: 49, child: Text(
          remaining == null ? '—' : '${remaining.toStringAsFixed(1)}%',
          textAlign: TextAlign.end,
          style: const TextStyle(color: DeckColor.text,
            fontSize: 11, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 3),
      Padding(padding: const EdgeInsets.only(left: 63),
        child: Text(resetTime, key: Key('micro-reset-time-$kind'),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: DeckColor.muted,
            fontSize: 9, letterSpacing: .2))),
    ]);
  }

}

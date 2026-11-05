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
            _microAction(
              key: const Key('micro-pin'),
              icon: state.alwaysOnTop
                ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              tooltip: state.alwaysOnTop ? 'Unpin window' : 'Always on Top',
              color: state.alwaysOnTop ? DeckColor.gold : DeckColor.muted,
              onTap: state.ready ? toggleAlwaysOnTop : null),
            _microAction(
              key: const Key('micro-monitor'),
              icon: Icons.dashboard_outlined, tooltip: 'Monitor view',
              color: DeckColor.aqua,
              onTap: () => state.edit(microMode: false, compactMode: true)),
            _microAction(
              key: const Key('micro-full'),
              icon: Icons.open_in_full_rounded, tooltip: 'Full view',
              color: DeckColor.mint,
              onTap: () => state.edit(microMode: false, compactMode: false)),
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
    final remaining = value is num ? value.toDouble() : null;
    return Row(children: [
      SizedBox(width: 56, child: Text(label, maxLines: 1,
        style: TextStyle(color: accent, fontSize: 9.5,
          fontWeight: FontWeight.w800, letterSpacing: .5))),
      const SizedBox(width: 7),
      Expanded(child: AeroLiquidBar(
        amount: remaining, appearance: state.appearance,
        kind: kind, height: 12)),
      const SizedBox(width: 9),
      SizedBox(width: 49, child: Text(
        remaining == null ? '—' : '${remaining.toStringAsFixed(1)}%',
        textAlign: TextAlign.end,
        style: const TextStyle(color: DeckColor.text,
          fontSize: 11, fontWeight: FontWeight.w800))),
    ]);
  }

  Widget _microAction({required Key key, required IconData icon,
      required String tooltip, required Color color,
      required VoidCallback? onTap}) => SizedBox(
    width: 33, height: 33,
    child: IconButton(
      key: key,
      tooltip: tooltip, onPressed: onTap, padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 33, height: 33),
      icon: Icon(icon, size: 18, color: color),
    ),
  );
}

part of 'main.dart';

/// Desktop workspace: two genuinely different zones, not coordinate-painted
/// WinForms rows. At the native default size every essential control is visible.
extension _DashboardFrame on _SchedulerHomeState {
  Widget _fullDeck() {
    final state = controller!;
    return DeckAtmosphere(
      child: LayoutBuilder(builder: (context, bounds) {
        final width = math.max(bounds.maxWidth, 1240.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
              child: Column(children: [
                SizedBox(height: 72, child: _deckHeader(state)),
                const SizedBox(height: 17),
                SizedBox(height: 660, child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 7, child: Column(children: [
                      SizedBox(height: 320, child: _sourceCard(state)),
                      const SizedBox(height: 16),
                      SizedBox(height: 324, child: _launchCard(state)),
                    ])),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: _monitorColumn(state)),
                  ],
                )),
                if (state.error != null &&
                    !state.error!.startsWith('Usage unavailable:')) ...[
                  const SizedBox(height: 10),
                  _dashboardError(state.error!),
                ],
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _deckHeader(SchedulerController state) => Row(children: [
    Container(
      width: 53, height: 53,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: const LinearGradient(
          colors: [DeckColor.coral, DeckColor.rose, DeckColor.iris],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: DeckColor.coral.withValues(alpha: .25),
            blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: const Icon(Icons.play_circle_fill_rounded,
        color: DeckColor.voidInk, size: 30),
    ),
    const SizedBox(width: 16),
    const Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center, children: [
      DeckOverline('CODEX  /  RESUME SCHEDULER',
        color: DeckColor.muted),
      SizedBox(height: 1),
      Text('Continuum.',
        style: TextStyle(
          color: DeckColor.text, fontSize: 30,
          fontWeight: FontWeight.w900, letterSpacing: -1.25)),
    ]),
    const Spacer(),
    DeckInfo(state.ready ? 'CONNECTED' : 'CONNECTING',
      color: state.ready ? DeckColor.mint : DeckColor.gold,
      icon: state.ready ? Icons.link_rounded : Icons.sync_rounded),
    const SizedBox(width: 12),
    DeckAction(label: 'Logs', icon: Icons.folder_outlined,
      compact: true, onTap: openLogs, tone: DeckColor.aqua),
    const SizedBox(width: 9),
    DeckAction(label: 'History', icon: Icons.history_rounded,
      compact: true, onTap: historyDialog, tone: DeckColor.iris),
    const SizedBox(width: 9),
    DeckAction(label: 'Appearance', icon: Icons.palette_outlined,
      compact: true, onTap: appearanceDialog, tone: DeckColor.rose),
    const SizedBox(width: 9),
    DeckAction(label: 'Monitor', icon: Icons.dashboard_customize_outlined,
      compact: true, onTap: () => state.edit(compactMode: true),
      tone: DeckColor.mint),
  ]);

  /// Compact is a separate monitoring instrument, not a squeezed form.
  Widget _compactDeck() {
    final state = controller!;
    final runs = state.upcoming;
    final windows = state.quotaWindows;
    return DeckAtmosphere(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const DeckBeacon(color: DeckColor.mint),
          const SizedBox(width: 7),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DeckOverline('CONTINUUM  /  LIVE MONITOR',
                color: DeckColor.aqua),
              SizedBox(height: 4),
              Text('On watch.',
                style: TextStyle(color: DeckColor.text,
                  fontSize: 26, fontWeight: FontWeight.w900)),
            ],
          )),
          DeckAction(label: 'Full view', icon: Icons.open_in_full_rounded,
            compact: true, tone: DeckColor.mint,
            onTap: () => state.edit(compactMode: false)),
        ]),
        const SizedBox(height: 17),
        Row(children: [
          const Expanded(child: DeckOverline('CAPACITY',
            color: DeckColor.muted)),
          Text(state.quotaModel, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DeckColor.subtle, fontSize: 10)),
        ]),
        const SizedBox(height: 9),
        SizedBox(height: 133, child: _capacityCard(
          window: windows.isNotEmpty ? windows.first : null,
          label: 'Five-hour', kind: 'quota', accent: DeckColor.mint,
          top: const Color(0xff17443f), bottom: const Color(0xff172a3a),
          error: state.error)),
        const SizedBox(height: 11),
        SizedBox(height: 133, child: _capacityCard(
          window: windows.length > 1 ? windows[1] : null,
          label: 'Weekly', kind: 'weekly', accent: DeckColor.iris,
          top: const Color(0xff382956), bottom: const Color(0xff242440),
          error: state.error)),
        if (runs.isNotEmpty) ...[
          const SizedBox(height: 17),
          const DeckOverline('NEXT IN FLIGHT', color: DeckColor.gold),
          const SizedBox(height: 8),
          DeckSurface(
            top: const Color(0xff332940),
            bottom: const Color(0xff1e2438),
            accent: DeckColor.gold,
            radius: 18,
            padding: const EdgeInsets.all(10),
            child: _runTile(runs.first),
          ),
        ],
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: DeckAction(label: 'History',
            compact: true, icon: Icons.history_rounded,
            tone: DeckColor.iris, onTap: historyDialog)),
          const SizedBox(width: 8),
          Expanded(child: DeckAction(label: 'Appearance',
            compact: true, icon: Icons.palette_outlined,
            tone: DeckColor.rose, onTap: appearanceDialog)),
          const SizedBox(width: 8),
          DeckAction(label: 'Logs', compact: true,
            icon: Icons.folder_outlined,
            tone: DeckColor.aqua, onTap: openLogs),
        ]),
        if (state.error != null &&
            !state.error!.startsWith('Usage unavailable:')) ...[
          const SizedBox(height: 12),
          _dashboardError(state.error!),
        ],
      ]),
    ));
  }

  Widget _dashboardError(String message) => DecoratedBox(
    decoration: BoxDecoration(
      color: DeckColor.rose.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: DeckColor.rose.withValues(alpha: .44)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded,
          color: DeckColor.rose, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message, maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DeckColor.text, fontSize: 11))),
      ]),
    ),
  );
}

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
              padding: const EdgeInsets.fromLTRB(26, 12, 26, 12),
              child: Column(children: [
                SizedBox(height: 62, child: _deckHeader(state)),
                const SizedBox(height: 12),
                SizedBox(height: 702, child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 7, child: Column(children: [
                      SizedBox(height: 320, child: _sourceCard(state)),
                      const SizedBox(height: 16),
                      SizedBox(height: 366, child: _launchCard(state)),
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

  Widget _deckHeader(SchedulerController state) {
    final loadFailed = !state.ready &&
        (state.error?.startsWith('Refresh failed:') ?? false);
    return Row(children: [
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
    DeckInfo(state.ready ? 'CONNECTED' : loadFailed ? 'LOAD FAILED' : 'CONNECTING',
      color: state.ready ? DeckColor.mint : loadFailed ? DeckColor.rose : DeckColor.gold,
      icon: state.ready ? Icons.link_rounded :
        loadFailed ? Icons.error_outline_rounded : Icons.sync_rounded),
    const SizedBox(width: 12),
    viewMenu(),
    const SizedBox(width: 8),
    pinButton(),
    const SizedBox(width: 8),
    moreMenu(),
    ]);
  }

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
          viewMenu(tight: true),
          const SizedBox(width: 6),
          pinButton(),
          const SizedBox(width: 6),
          moreMenu(),
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
          if (stringField(runs.first, 'Status') == 'Running') ...[
            const SizedBox(height: 8),
            _liveActivityPanel(state, stringField(runs.first, 'Name')),
          ],
        ],
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

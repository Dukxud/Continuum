import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aero_appearance.dart';
import 'aero_bar.dart';
import 'dashboard_skin.dart';

/// The same v1.16 appearance schema in a purpose-built, live material studio.
/// Two tabs, no scrolling and no explicit Save step.
class AeroAppearanceEditor extends StatefulWidget {
  const AeroAppearanceEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final AeroAppearance initial;
  final ValueChanged<AeroAppearance> onChanged;

  @override
  State<AeroAppearanceEditor> createState() => _AeroAppearanceEditorState();
}

class _AeroAppearanceEditorState extends State<AeroAppearanceEditor> {
  late AeroAppearance draft;

  @override
  void initState() {
    super.initState();
    draft = widget.initial;
  }

  void preview(AeroAppearance value) {
    setState(() => draft = value);
    widget.onChanged(value);
  }

  Future<void> chooseCustom(String kind) async {
    final selected = draft.selection(kind);
    final fallback =
        '#${draft.color(kind).toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    final original = selected.startsWith('#') ? selected : fallback;
    String candidate = original;
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, repaint) {
          final valid = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(candidate);
          return AlertDialog(
            title: const Text('Custom RGB color'),
            content: SizedBox(
              width: 270,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: original,
                    autofocus: true,
                    maxLength: 7,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-fA-F#]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Hex color · #RRGGBB',
                    ),
                    onChanged: (value) => repaint(() => candidate = value),
                  ),
                  if (valid)
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(
                          int.parse('FF${candidate.substring(1)}', radix: 16),
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(dialog, candidate.toUpperCase())
                    : null,
                child: const Text('Apply color'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      preview(draft.withColor(kind, result));
    }
  }

  Widget _caption(String value) => Text(
    value.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: DeckColor.muted,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
    ),
  );

  Widget _paletteRow(String title, String kind) {
    final value = draft.selection(kind);
    final choice = AeroAppearance.presetColors.containsKey(value)
        ? value
        : 'custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(title),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: DeckSelect<String>(
                  name: '$kind-pigment',
                  value: choice,
                  items: [
                    for (final id in AeroAppearance.presetColors.keys)
                      DropdownMenuItem(
                        value: id,
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 17,
                              decoration: BoxDecoration(
                                color: AeroAppearance.presetColors[id],
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                AeroAppearance.presetNames[id]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text(
                        value.startsWith('#') ? 'Custom  $value' : 'Custom RGB',
                      ),
                    ),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    if (id == 'custom') {
                      chooseCustom(kind);
                    } else {
                      preview(draft.withColor(kind, id));
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            DeckAction(
              label: 'RGB',
              compact: true,
              tone: DeckColor.rose,
              onTap: () => chooseCustom(kind),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paletteTab() => Row(
    children: [
      Expanded(
        flex: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _paletteRow('5-hour color', 'quota'),
            const SizedBox(height: 10),
            _paletteRow('Weekly color', 'weekly'),
            const SizedBox(height: 10),
            _paletteRow('Countdown color', 'time'),
            const SizedBox(height: 10),
            _paletteRow('Working color', 'working'),
          ],
        ),
      ),
      const SizedBox(width: 18),
      Expanded(flex: 6, child: _materialPreview()),
    ],
  );

  Widget _materialPreview() => DeckSurface(
    top: const Color(0xff2f254a),
    bottom: const Color(0xff18293b),
    accent: DeckColor.iris,
    radius: 19,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DeckOverline('LIVE MATERIAL', color: DeckColor.iris),
        const SizedBox(height: 5),
        const Text(
          'Under the light.',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: DeckColor.text,
          ),
        ),
        const SizedBox(height: 22),
        _sampleBar('FIVE-HOUR', '68%', 'quota', 68),
        const SizedBox(height: 14),
        _sampleBar('WEEKLY', '50%', 'weekly', 50),
        const SizedBox(height: 14),
        _sampleBar('COUNTDOWN', '75%', 'time', 75),
        const SizedBox(height: 14),
        _sampleBar('WORKING', 'LIVE', 'working', null, working: true),
      ],
    ),
  );

  Widget _sampleBar(
    String title,
    String percentage,
    String kind,
    double? amount, {
    bool working = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: _caption(title)),
          Text(
            percentage,
            style: const TextStyle(
              color: DeckColor.text,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      AeroLiquidBar(
        amount: amount,
        working: working,
        kind: kind,
        appearance: draft,
        height: 16,
      ),
    ],
  );

  Widget _numberSelect(
    String label,
    int value,
    List<String> options,
    ValueChanged<int> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _caption(label),
      const SizedBox(height: 5),
      SizedBox(
        height: 42,
        child: DeckSelect<int>(
          name: label,
          value: value,
          items: List.generate(
            options.length,
            (index) => DropdownMenuItem(
              value: index,
              child: Text(
                options[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          onChanged: (next) {
            if (next != null) changed(next);
          },
        ),
      ),
    ],
  );

  Widget _settingSlider(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: _caption(label)),
          Text(
            '$value%',
            style: const TextStyle(
              fontSize: 11,
              color: DeckColor.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      // Keep Slider's OverlayPortal inside a local Overlay for Windows
      // accessibility. See flutter/flutter#190357.
      SizedBox(
        height: 34,
        child: Overlay.wrap(
          alwaysSizeToContent: true,
          clipBehavior: Clip.none,
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            activeColor: DeckColor.coral,
            onChanged: (next) => changed(next.round()),
          ),
        ),
      ),
    ],
  );

  Widget _opticsTab(String? diagnostic) => Row(
    children: [
      Expanded(
        flex: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _numberSelect('Liquid material', draft.finish, const [
              'Optical glass',
              'Mirror enamel',
              'Iridescent pearl',
            ], (value) => preview(draft.copyWith(finish: value))),
            const SizedBox(height: 10),
            _numberSelect('Studio lighting', draft.lighting, const [
              'Product studio',
              'Aero daylight',
              'Neon showroom',
            ], (value) => preview(draft.copyWith(lighting: value))),
            const SizedBox(height: 10),
            _settingSlider(
              'Reflection strength',
              draft.shimmer,
              0,
              200,
              (value) => preview(draft.copyWith(shimmer: value)),
            ),
            const SizedBox(height: 5),
            _settingSlider(
              'Reflection speed',
              draft.speed,
              25,
              300,
              (value) => preview(draft.copyWith(speed: value)),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Checkbox(
                  value: draft.aero,
                  activeColor: DeckColor.coral,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (value) {
                    if (value != null) preview(draft.copyWith(aero: value));
                  },
                ),
                const Expanded(
                  child: Text(
                    'Enable Aero Liquid optics',
                    style: TextStyle(fontSize: 11.5, color: DeckColor.text),
                  ),
                ),
              ],
            ),
            if (diagnostic != null)
              Text(
                'GPU optics unavailable: $diagnostic',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: DeckColor.gold),
              ),
          ],
        ),
      ),
      const SizedBox(width: 18),
      Expanded(flex: 6, child: _materialPreview()),
    ],
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(10),
    child: SizedBox(
      width: 742,
      height: 595,
      child: DeckSurface(
        top: const Color(0xff252942),
        bottom: const Color(0xff151f30),
        accent: DeckColor.iris,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [DeckColor.rose, DeckColor.iris],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.palette_rounded,
                      color: DeckColor.voidInk,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Material lab.',
                          style: TextStyle(
                            color: DeckColor.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Changes are saved automatically.',
                          style: TextStyle(
                            color: DeckColor.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close appearance editor',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: DeckColor.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const TabBar(
                labelColor: DeckColor.text,
                unselectedLabelColor: DeckColor.muted,
                indicatorColor: DeckColor.rose,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Colors'),
                  Tab(text: 'Optics'),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: TabBarView(
                  children: [_paletteTab(), _opticsTab(AeroAssets.shaderError)],
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  DeckAction(
                    label: 'Defaults',
                    tone: DeckColor.iris,
                    compact: true,
                    onTap: () => preview(AeroAppearance.defaults),
                  ),
                  const Spacer(),
                  const Text(
                    'PREVIEW IS LIVE',
                    style: TextStyle(
                      color: DeckColor.muted,
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 118,
                    child: DeckAction(
                      label: 'Done',
                      primary: true,
                      tone: DeckColor.rose,
                      compact: true,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

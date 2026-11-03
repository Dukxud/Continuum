import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'aero_appearance.dart';
import 'aero_bar.dart';

/// A transactional, live-preview editor for the v1.16 appearance contract.
/// The caller applies onPreview temporarily and restores initial on Cancel.
class AeroAppearanceEditor extends StatefulWidget {
  const AeroAppearanceEditor({
    super.key,
    required this.initial,
    required this.onPreview,
  });
  final AeroAppearance initial;
  final ValueChanged<AeroAppearance> onPreview;

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

  void preview(AeroAppearance next) {
    setState(() => draft = next);
    widget.onPreview(next);
  }

  Future<void> chooseCustom(String kind) async {
    final current = draft.selection(kind);
    final existing = current.startsWith('#') ? current :
      '#' + draft.color(kind).toARGB32().toRadixString(16).substring(2).toUpperCase();
    final controller = TextEditingController(text: existing);
    String? candidate = existing;
    try {
      final selected = await showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(builder: (context, repaint) {
          final valid = candidate != null &&
            RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(candidate!);
          return AlertDialog(
            title: const Text('Choose custom RGB color'),
            content: SizedBox(width: 250, child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 7,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]'))],
                  decoration: const InputDecoration(labelText: 'Hex color · #RRGGBB'),
                  onChanged: (value) => repaint(() => candidate = value),
                ),
                if (valid)
                  Container(height: 26, decoration: BoxDecoration(
                    color: Color(int.parse('FF' + candidate!.substring(1), radix: 16)),
                    borderRadius: BorderRadius.circular(5))),
              ],
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
              FilledButton(onPressed: valid ? () => Navigator.pop(dialog, candidate!.toUpperCase()) : null,
                child: const Text('Use color')),
            ],
          );
        }),
      );
      if (selected != null && mounted) {
        preview(draft.withColor(kind, selected));
      }
    } finally {
      // Dialog TextField stays mounted until after route exit animation.
      // Dispose after the route's future has completed, not during editing.
      controller.dispose();
    }
  }

  Widget colorEditor(String kind, String caption, double amount, {bool working = false}) {
    final selected = draft.selection(kind);
    final value = AeroAppearance.presetColors.containsKey(selected) ? selected : 'custom';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(caption,
            style: const TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 192, child: DropdownButtonFormField<String>(
            isExpanded: true, value: value,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final name in AeroAppearance.presetColors.keys)
                DropdownMenuItem(value: name, child: Row(children: [
                  CircleAvatar(backgroundColor: AeroAppearance.presetColors[name],
                    radius: 7),
                  const SizedBox(width: 7),
                  Expanded(child: Text(AeroAppearance.presetNames[name]!,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                ])),
              const DropdownMenuItem(value: 'custom', child: Text('Custom RGB')),
            ],
            onChanged: (choice) {
              if (choice == null) return;
              if (choice == 'custom') {
                chooseCustom(kind);
              } else {
                preview(draft.withColor(kind, choice));
              }
            },
          )),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => chooseCustom(kind),
            child: const Text('Choose...')),
        ]),
        const SizedBox(height: 7),
        AeroLiquidBar(amount: working ? null : amount,
          appearance: draft, kind: kind, working: working),
      ]),
    );
  }

  Widget settingSlider(String title, int value, int min, int max,
    ValueChanged<int> changed) {
    return Row(children: [
      Expanded(flex: 3, child: Text(title)),
      Expanded(flex: 5, child: Slider(
        value: value.toDouble(), min: min.toDouble(), max: max.toDouble(),
        onChanged: (value) => changed(value.round()))),
      SizedBox(width: 50, child: Text(value.toString() + '%',
        textAlign: TextAlign.end)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 590, maxHeight: 760),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Customize progress bars',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('Changes preview live. Cancel restores the previous appearance.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ])),
        const Divider(height: 1),
        Flexible(child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          shrinkWrap: true, children: [
          colorEditor('quota', '5-hour color', 72),
          colorEditor('weekly', 'Weekly color', 45),
          colorEditor('time', 'Countdown color', 63),
          colorEditor('working', 'Working color', 100, working: true),
          const Divider(height: 22),
          DropdownButtonFormField<int>(
            isExpanded: true, value: draft.finish,
            decoration: const InputDecoration(labelText: 'Liquid material'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Optical glass')),
              DropdownMenuItem(value: 1, child: Text('Mirror enamel')),
              DropdownMenuItem(value: 2, child: Text('Iridescent pearl')),
            ],
            onChanged: (v) { if (v != null) preview(draft.copyWith(finish: v)); },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true, value: draft.lighting,
            decoration: const InputDecoration(labelText: 'Studio lighting'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Product studio')),
              DropdownMenuItem(value: 1, child: Text('Aero daylight')),
              DropdownMenuItem(value: 2, child: Text('Neon showroom')),
            ],
            onChanged: (v) { if (v != null) preview(draft.copyWith(lighting: v)); },
          ),
          const SizedBox(height: 10),
          settingSlider('Reflection strength', draft.shimmer, 0, 200,
            (v) => preview(draft.copyWith(shimmer: v))),
          settingSlider('Reflection speed', draft.speed, 25, 300,
            (v) => preview(draft.copyWith(speed: v))),
          CheckboxListTile(
            value: draft.aero,
            onChanged: (v) { if (v != null) preview(draft.copyWith(aero: v)); },
            title: const Text('Enable Aero Liquid optics'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (AeroAssets.shaderError != null)
            Text('GPU shader unavailable; using native Windows pixels: ' +
              AeroAssets.shaderError!, style: const TextStyle(fontSize: 11,
                color: Colors.deepOrange)),
        ])),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            TextButton(
              onPressed: () => preview(AeroAppearance.defaults),
              child: const Text('Defaults')),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => Navigator.pop(context, draft),
              child: const Text('Save and close')),
          ])),
      ]),
    ));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'aero_appearance.dart';
import 'aero_bar.dart';
import 'windows_icons.dart';

/// Live appearance editor: changes are persisted by the owning controller.
/// The two pages keep every control visible without scrolling.
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

  void preview(AeroAppearance next) {
    setState(() => draft = next);
    widget.onChanged(next);
  }

  Future<void> chooseCustom(String kind) async {
    final current = draft.selection(kind);
    final existing = current.startsWith('#') ? current :
      '#' + draft.color(kind).toARGB32().toRadixString(16).substring(2).toUpperCase();
    String? candidate = existing;
    final selected = await showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(builder: (context, repaint) {
          final valid = candidate != null &&
            RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(candidate!);
          return AlertDialog(
            title: const Text('Choose custom RGB color'),
            content: SizedBox(width: 250, child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  initialValue: existing,
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
  }

  Widget _at(double x,double y,double width,double height,Widget child) =>
    Positioned(left:x,top:y,width:width,height:height,child:child);

  Widget _label(String text,{bool bold=false,Color color=const Color(0xff253a58),double font=13}) =>
    Align(alignment:Alignment.centerLeft,child:Text(text,
      maxLines:1,overflow:TextOverflow.ellipsis,
      style:TextStyle(fontFamily:'Segoe UI',fontSize:font,color:color,
        fontWeight:bold?FontWeight.bold:FontWeight.normal)));

  Widget _nativeButton(String label,VoidCallback? action,{bool primary=false}) =>
    OutlinedButton(onPressed:action,
      style:OutlinedButton.styleFrom(
        backgroundColor:primary?const Color(0xff2277a1):const Color(0xff52749b),
        foregroundColor:Colors.white,
        shape:const RoundedRectangleBorder(borderRadius:BorderRadius.zero),
        padding:EdgeInsets.zero),
      child:Text(label,style:const TextStyle(fontFamily:'Segoe UI',fontSize:13)));

  Widget _selectSurface<T>({
    required Key key,required T? selected,required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  })=>Container(
    padding:const EdgeInsets.symmetric(horizontal:6),
    decoration:BoxDecoration(color:const Color(0xfffbfdff),
      border:Border.all(color:const Color(0xffb8c6d8))),
    child:DropdownButtonHideUnderline(child:DropdownButton<T>(
      key:key,value:selected,isExpanded:true,isDense:true,
      items:items,onChanged:onChanged,
      style:const TextStyle(fontFamily:'Segoe UI',fontSize:13,color:Color(0xff253a58)),
      icon:const WindowsCaret(),
    )),
  );

  Widget _colorSelect(String kind) {
    final selected = draft.selection(kind);
    final choice = AeroAppearance.presetColors.containsKey(selected)?selected:'custom';
    return _selectSurface<String>(
      key:ValueKey(kind+':'+selected), selected:choice,
      items:[
        for(final key in AeroAppearance.presetColors.keys)
          DropdownMenuItem(value:key,child:Row(children:[
            Container(width:25,height:15,
              decoration:BoxDecoration(color:AeroAppearance.presetColors[key],
                border:Border.all(color:const Color(0xff657387)))),
            const SizedBox(width:9),
            Expanded(child:Text(AeroAppearance.presetNames[key]!,
              maxLines:1,overflow:TextOverflow.ellipsis)),
          ])),
        DropdownMenuItem(value:'custom',child:Text(selected.startsWith('#')
          ? 'Custom  '+selected : 'Custom RGB')),
      ],
      onChanged:(value){
        if(value==null)return;
        if(value=='custom'){chooseCustom(kind);return;}
        preview(draft.withColor(kind,value));
      });
  }

  Widget _colorRow(String title,String kind,double top)=>Stack(children:[
    _at(19,top+5,140,25,_label(title)),
    _at(163,top,264,30,_colorSelect(kind)),
    _at(438,top,104,29,_nativeButton('Choose...',()=>chooseCustom(kind))),
  ]);

  Widget _previewSurface(){
    const captions=['5-HOUR   68%','WEEKLY   50%','COUNTDOWN   75%',
      'WORKING   duration unknown'];
    const kinds=['quota','weekly','time','working'];
    const values=[68.0,50.0,75.0,100.0];
    return Container(color:Colors.white,
      child:Stack(children:[
        for(var index=0;index<4;index++)...[
          _at(16,4+index*45,487,23,_label(captions[index],bold:true,font:12)),
          _at(16,25+index*45,488,17,AeroLiquidBar(
            amount:index==3?null:values[index],
            kind:kinds[index],appearance:draft,working:index==3)),
        ],
      ]));
  }

  Widget _opticsPreview() {
    const captions = ['5-HOUR   68%', 'WEEKLY   50%', 'COUNTDOWN   75%',
      'WORKING   duration unknown'];
    const kinds = ['quota', 'weekly', 'time', 'working'];
    const values = [68.0, 50.0, 75.0, 100.0];
    return Container(color: Colors.white, child: Stack(children: [
      for (var index = 0; index < 4; index++) ...[
        _at(12 + (index % 2) * 252, 8 + (index ~/ 2) * 62, 239, 21,
          _label(captions[index], bold: true, font: 12)),
        _at(12 + (index % 2) * 252, 30 + (index ~/ 2) * 62, 239, 17,
          AeroLiquidBar(amount: index == 3 ? null : values[index],
            kind: kinds[index], appearance: draft, working: index == 3)),
      ],
    ]));
  }

  Widget _enumSelect(int value,List<String> names,ValueChanged<int> onChange) =>
    _selectSurface<int>(
      key:ValueKey('enum:'+names.first+':'+value.toString()),
      selected:value,
      items:List.generate(names.length,(i)=>DropdownMenuItem(
        value:i,child:Text(names[i],overflow:TextOverflow.ellipsis))),
      onChanged:(v){if(v!=null)onChange(v);});

  Widget _settingsSlider(String label,int value,int low,int high,double y,
      ValueChanged<int> changed)=>Stack(children:[
    _at(19,y+5,145,24,_label(label)),
    // Flutter's Material Slider uses OverlayPortal. A Slider inside a pushed
    // modal can orphan accessibility nodes on Windows (flutter/flutter#190357).
    // Keep the portal inside a local Overlay; preserve slider semantics.
    _at(158,y,315,40,Overlay.wrap(
      alwaysSizeToContent:true,clipBehavior:Clip.none,
      child:Slider(value:value.toDouble(),min:low.toDouble(),
        max:high.toDouble(),onChanged:(v)=>changed(v.round())))),
    _at(481,y+4,62,25,Align(alignment:Alignment.centerRight,
      child:Text(value.toString()+'%',style:const TextStyle(fontFamily:'Segoe UI',fontSize:13)))),
  ]);

  Widget _colorsTab() => Stack(children: [
    _at(0, 2, 566, 30, _colorRow('5-hour color', 'quota', 0)),
    _at(0, 40, 566, 30, _colorRow('Weekly color', 'weekly', 0)),
    _at(0, 78, 566, 30, _colorRow('Countdown color', 'time', 0)),
    _at(0, 116, 566, 30, _colorRow('Working color', 'working', 0)),
    _at(19, 164, 524, 190, Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xffb8c6d8))),
      child: _previewSurface())),
  ]);

  Widget _opticsTab(String? diagnostic) => Stack(children: [
    _at(19, 12, 140, 25, _label('Liquid material')),
    _at(163, 7, 379, 30, _enumSelect(draft.finish,
      const ['Optical glass', 'Mirror enamel', 'Iridescent pearl'],
      (v) => preview(draft.copyWith(finish: v)))),
    _at(19, 50, 140, 25, _label('Studio lighting')),
    _at(163, 45, 379, 30, _enumSelect(draft.lighting,
      const ['Product studio', 'Aero daylight', 'Neon showroom'],
      (v) => preview(draft.copyWith(lighting: v)))),
    _at(0, 87, 566, 40, _settingsSlider('Reflection strength',
      draft.shimmer, 0, 200, 0, (v) => preview(draft.copyWith(shimmer: v)))),
    _at(0, 130, 566, 40, _settingsSlider('Reflection speed',
      draft.speed, 25, 300, 0, (v) => preview(draft.copyWith(speed: v)))),
    _at(20, 178, 522, 30, Row(children: [
      Checkbox(value: draft.aero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onChanged: (v) { if (v != null) preview(draft.copyWith(aero: v)); }),
      const SizedBox(width: 5),
      Expanded(child: _label('Enable Aero Liquid optics')),
    ])),
    _at(20, 207, 520, 23, _label(
      diagnostic != null ? 'Aero Liquid unavailable: ' + diagnostic :
        draft.aero ? 'Aero Liquid: Flutter GPU renderer' : 'Aero optics disabled',
      color: const Color(0xff666666), font: 12)),
    _at(19, 232, 524, 122, Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xffb8c6d8))),
      child: _opticsPreview())),
  ]);

  @override
  Widget build(BuildContext context) {
    final diagnostic = AeroAssets.shaderError;
    return Dialog(
      backgroundColor: const Color(0xfff6f9fd),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(width: 566, height: 514,
        child: DefaultTabController(length: 2, child: Stack(children: [
          _at(20, 12, 518, 26,
            _label('Adjust the material. See it change below.',
              font: 16, bold: true)),
          _at(20, 37, 525, 21,
            _label('Changes are saved automatically.', 
              color: const Color(0xff666666), font: 12)),
          _at(20, 58, 524, 46, const TabBar(
            labelColor: Color(0xff253a58),
            unselectedLabelColor: Color(0xff52647c),
            indicatorColor: Color(0xff2277a1),
            tabs: [Tab(text: 'Colors'), Tab(text: 'Optics')],
          )),
          _at(0, 105, 566, 354, TabBarView(children: [
            _colorsTab(),
            _opticsTab(diagnostic),
          ])),
          _at(19, 462, 524, 2,
            Container(color: const Color(0xffb8c6d8))),
          _at(19, 470, 98, 31, _nativeButton('Defaults',
            () => preview(AeroAppearance.defaults))),
          _at(442, 470, 100, 31, _nativeButton('Done',
            () => Navigator.pop(context), primary: true)),
        ]))),
    );
  }
}

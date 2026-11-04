part of 'main.dart';

// Coordinates, band colors and labels follow CodexUiForms.ps1,
// CodexUiPixelTheme.ps1 and Update-DashboardLayout in CodexDashboard.ps1.
// Flutter owns interactivity; the existing worker owns scheduling policy.
const _legacyBackground = Color(0xfff3f6fa);
const _legacyInk = Color(0xff273a53);
const _legacyInput = Color(0xffffffff);

/// Quiet card surface; liquid color belongs to the bars, not noisy borders.
class _LegacyBand extends StatelessWidget {
  const _LegacyBand({required this.fill, required this.accent});
  final Color fill;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: accent.withValues(alpha: .36)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff2a4469).withValues(alpha: .035),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: const SizedBox.expand(),
  );
}

class _LegacyButton extends StatelessWidget {
  const _LegacyButton(this.text, this.onPressed,{
    this.color = const Color(0xff55739b),
    this.primary = false,
  });
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = !enabled
      ? const Color(0xffe9edf3)
      : primary ? color : Color.lerp(color, Colors.white, .89)!;
    final ink = !enabled
      ? const Color(0xff7a8597)
      : primary ? Colors.white : Color.lerp(color, const Color(0xff1d2f48), .56)!;
    final edge = !enabled
      ? const Color(0xffd7dfe9)
      : primary ? color : Color.lerp(color, Colors.white, .63)!;
    final radius = BorderRadius.circular(6);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: fill,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: edge),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Segoe UI',
                color: ink,
                fontSize: 13,
                fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegacyInputBorder extends OutlineInputBorder {
  const _LegacyInputBorder()
    : super(
        borderSide: const BorderSide(color: Color(0xffcad5e3)),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      );
}

extension _LegacySchedulerVisuals on _SchedulerHomeState {
  Widget _at(double x,double y,double width,double height,Widget child) =>
    Positioned(left:x,top:y,width:width,height:height,child:child);

  Widget _label(String content,{double fontSize=13,bool bold=false,Color color=_legacyInk}) =>
    Align(alignment:Alignment.centerLeft, child:Text(content,
      maxLines:1,overflow:TextOverflow.ellipsis,
      style:TextStyle(fontFamily:'Segoe UI',color:color,fontSize:fontSize,
        fontWeight:bold?FontWeight.bold:FontWeight.normal)));

  Widget _textbox(TextEditingController text, ValueChanged<String> change,
      {String? hint, Key? key}) => TextField(
    key:key,controller:text,
    onChanged:change,
    maxLines:1,
    style:const TextStyle(fontFamily:'Segoe UI',fontSize:13,color:_legacyInk),
    decoration:InputDecoration(
      hintText:hint,isDense:true,filled:true,fillColor:_legacyInput,
      contentPadding:const EdgeInsets.symmetric(horizontal:7,vertical:5),
      enabledBorder:const _LegacyInputBorder(),
      focusedBorder:const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide:BorderSide(color:Color(0xff457fb6),width:1.5)),
    ));

  Widget _combo<T>({
    required String name,required T? selected,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  })=>Container(
    padding:const EdgeInsets.symmetric(horizontal:6),
    decoration:BoxDecoration(color:_legacyInput,
      borderRadius: BorderRadius.circular(6),
      border:Border.all(color:const Color(0xffcad5e3))),
    child:DropdownButtonHideUnderline(child:DropdownButton<T>(
      key:ValueKey(name+':'+selected.toString()),
      value:selected,
      isExpanded:true,isDense:true,
      icon:const WindowsCaret(color:_legacyInk),
      style:const TextStyle(fontFamily:'Segoe UI',fontSize:13,color:_legacyInk),
      items:items,onChanged:onChanged,
    )),
  );

  Widget _datePickerControl(DateTime selected) => Material(
    color: _legacyInput,
    child: InkWell(
      onTap: pickTime,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xffcad5e3))),
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Row(children: [
          Expanded(child: Text(
            _dateLabel(selected, long: true),
            key: const Key('selected-run-time-label'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Segoe UI',
              fontSize: 12, color: _legacyInk))),
          Container(
            width: 27,
            alignment: Alignment.center,
            decoration: const BoxDecoration(border: Border(
              left: BorderSide(color: Color(0xffc4cfde)))),
            child: const WindowsCalendarGlyph()),
          const WindowsCaret(color:_legacyInk),
        ]),
      ),
    ),
  );

  String _dateLabel(DateTime date,{bool long=false}) {
    const days=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    String d(int x)=>x.toString().padLeft(2,'0');
    final hour=date.hour%12==0?12:date.hour%12;
    if(long) return days[date.weekday-1]+' '+months[date.month-1]+' '+
      d(date.day)+', '+date.year.toString()+'  '+d(hour)+':'+d(date.minute)+
      ':'+d(date.second)+(date.hour>=12?' PM':' AM');
    return days[date.weekday-1]+' '+months[date.month-1]+' '+date.day.toString()+
      ', '+hour.toString()+':'+d(date.minute)+(date.hour>=12?' PM':' AM');
  }

  Widget _usageSurface(Map<String,dynamic>? window,String fallback,String kind) {
    final state=controller!;
    final remainingValue=field(window,'remainingPercent');
    final remaining=remainingValue is num?remainingValue.toDouble():null;
    final seconds=field(window,'resetsAt');
    final reset=seconds is num && seconds>0
      ? DateTime.fromMillisecondsSinceEpoch(seconds.toInt()*1000):null;
    final title=stringField(window,'label').isEmpty?fallback:stringField(window,'label');
    final body=<Widget>[
      _at(0,0,428,108,_LegacyBand(
        fill:kind=='quota'?const Color(0xffe7f8f2):const Color(0xffe7f5fc),
        accent:kind=='quota'?const Color(0xff219a74):const Color(0xff188fb5))),
      _at(12,10,225,27,_label(title,fontSize:13,bold:true)),
      _at(237,7,176,32,Align(alignment:Alignment.centerRight,
        child:Text(remaining==null?'Unavailable':remaining.toStringAsFixed(1)+'% remaining',
          maxLines:1,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontFamily:'Segoe UI',color:_legacyInk,fontSize:15,fontWeight:FontWeight.bold)))),
      _at(12,44,400,17,AeroLiquidBar(amount:remaining,appearance:state.appearance,kind:kind)),
      _at(12,72,400,24,Tooltip(
        message:window==null && state.error != null ? state.error! : '',
        child:_label(window==null && state.error?.startsWith('Usage unavailable:')==true
          ? 'Usage unavailable; retrying automatically'
          : reset==null?'Reset time unavailable':'Resets '+_dateLabel(reset),
          fontSize:12,color:const Color(0xff666666)))),
    ];
    return SizedBox(width:428,height:108,child:Stack(children:body));
  }

  Widget _parityHeader({required bool compact}) {
    final name=compact?'Codex Scheduler':'Schedule a continuation';
    return Stack(children:[
      _at(18,11,compact?264:500,38,_label(name,fontSize:compact?18:20,bold:true)),
      if(!compact) _at(574,15,140,32,
        _LegacyButton('Appearance...',appearanceDialog,color:const Color(0xff52749b))),
      _at(compact?298:728,13,compact?148:170,38,
        _legacyToggleButton(compact)),
    ]);
  }

  Widget _legacyToggleButton(bool compact) => Material(
    color:compact?const Color(0xff315fa7):const Color(0xffecf2fa),
    child:InkWell(onTap:()=>controller!.edit(compactMode:!compact),
      child:Container(
        alignment:Alignment.center,
        decoration:BoxDecoration(border:Border.all(color:compact?
          const Color(0xff244982):const Color(0xffa3bddb))),
        child:Text(compact?'Compact mode: ON':'Compact mode: OFF',
          style:TextStyle(fontFamily:'Segoe UI',fontWeight:FontWeight.w700,
            fontSize:13,color:compact?Colors.white:const Color(0xff284c80))),
      )),
  );

  /// Time and instruction are one operation. A single action column, with
  /// deliberate alignment and separation, replaces disconnected row buttons.
  Widget _schedulePanel(SchedulerController state) {
    final resetAt = state.resetSuggestion;
    return Stack(children: [
      const _LegacyBand(fill:Color(0xffe8f5fc),accent:Color(0xff2887b5)),
      _at(8,18,132,30,_label('Run at (local)')),
      _at(145,18,38,30,_LegacyButton('−',
        ()=>state.edit(time:stepRunAt(state.runAt,-1)))),
      _at(190,18,260,30,_datePickerControl(state.runAt)),
      _at(457,18,38,30,_LegacyButton('+',
        ()=>state.edit(time:stepRunAt(state.runAt,1)))),
      _at(502,18,185,30,_LegacyButton(resetAt==null?'Now +1':'Reset +1',
        ()=>state.edit(time:resetAt ?? suggestedRunAt()))),
      _at(8,65,132,30,_label('Instruction')),
      _at(145,65,542,30,_textbox(instruction,
        (v)=>state.edit(instruction:v))),
      _at(697,13,1,89,Container(color:const Color(0xffafc9d8))),
      _at(712,20,176,74,_LegacyButton('Schedule once',
        state.canSchedule?schedule:null,
        color:const Color(0xff2277a1),primary:true)),
    ]);
  }

  Widget _fullParityView() {
    final state=controller!;
    final runs=state.upcoming;
    final hasRuns=runs.isNotEmpty;
    final extraRows=math.min(runs.length,4);
    final gridHeight=hasRuns?35.0+extraRows*40.0:0.0;
    final actionY=hasRuns?536+gridHeight+13:490.0;
    final totalHeight=hasRuns?actionY+76:566.0;
    final modelOptions=state.models.map((m)=>DropdownMenuItem<String>(
      value:stringField(m,'id'),
      child:Text(stringField(m,'name').isEmpty?stringField(m,'id'):stringField(m,'name'),
        maxLines:1,overflow:TextOverflow.ellipsis))).toList();
    final validModel=state.models.any((m)=>stringField(m,'id')==state.model);
    final effortOptions=state.efforts.map((e)=>DropdownMenuItem<String>(value:e,child:Text(e))).toList();
    final children=<Widget>[
      _at(10,54,898,46,const _LegacyBand(fill:Color(0xffe8f1ff),accent:Color(0xff547fd2))),
      _at(10,102,898,44,const _LegacyBand(fill:Color(0xffe6f8f3),accent:Color(0xff168e87))),
      // Model configuration precedes one unified scheduling block: choose
      // the time, write the instruction, then schedule from that same area.
      _at(10,148,898,44,const _LegacyBand(fill:Color(0xfffff3e4),accent:Color(0xffc98737))),
      _at(10,194,898,115,_schedulePanel(state)),
      _at(18,61,125,30,_label('Conversation')),
      _at(155,61,743,30,_combo<String>(
        name:'session',selected:state.sessions.any((m)=>stringField(m,'Id')==state.sessionId)?state.sessionId:null,
        items:state.sessions.map((m)=>DropdownMenuItem<String>(
          value:stringField(m,'Id'),child:Text(stringField(m,'Display'),
            maxLines:1,overflow:TextOverflow.ellipsis))).toList(),
        onChanged:(id){repository.clear();state.selectSession(id);})),
      _at(18,108,132,30,_label('Repository root')),
      _at(155,108,605,30,_textbox(repository,
        (v)=>state.edit(repository:v),key:const Key('repository-root-field'))),
      _at(773,106,125,31,_LegacyButton('Browse',_browseRepo,color:const Color(0xff168e87))),
      _at(18,154,64,30,_label('Model')),
      _at(90,154,258,30,_combo<String>(name:'model',
        selected:validModel?state.model:null,
        items:modelOptions,onChanged:state.selectModel)),
      _at(361,154,86,30,_label('Reasoning')),
      _at(450,154,122,30,_combo<String>(name:'effort',
        selected:state.efforts.contains(state.effort)?state.effort:null,
        items:effortOptions,onChanged:(s){if(s!=null)state.edit(reasoning:s);})),
      _at(586,154,60,30,_label('Access')),
      _at(652,154,246,30,_combo<String>(name:'access',selected:state.access,
        items:const[
          DropdownMenuItem(value:'workspace-write',child:Text('Workspace write')),
          DropdownMenuItem(value:'yolo',child:Text('Full access (YOLO)')),
          DropdownMenuItem(value:'read-only',child:Text('Read-only test')),
        ],onChanged:(s){if(s!=null)state.edit(accessMode:s);})),
      _at(18,309,880,2,Container(color:const Color(0xffc6d2e3))),
      _at(18,322,300,30,_label('Usage remaining',fontSize:16,bold:true)),
      _at(18,358,428,108,_usageSurface(state.quotaWindows.isNotEmpty?state.quotaWindows.first:null,
        'Primary window','quota')),
      _at(470,358,428,108,_usageSurface(state.quotaWindows.length>1?state.quotaWindows[1]:null,
        'Secondary window','weekly')),
      if(hasRuns)...[
        _at(18,485,880,2,Container(color:const Color(0xffc6d2e3))),
        _at(18,499,400,30,_label('Upcoming runs (${runs.length})',fontSize:16,bold:true)),
        _at(18,536,880,gridHeight,_legacyRunGrid(runs)),
        _at(18,actionY,154,31,_LegacyButton('Cancel selected',
          !state.busy && runs.any((r)=>stringField(r,'Name')==selectedRun &&
            stringField(r,'Status')=='Scheduled') ? cancelSelected : null,
          color:const Color(0xffb86265))),
      ],
      _at(hasRuns?185:18,actionY,154,31,
        _LegacyButton('Open logs folder',openLogs,color:const Color(0xff52749b))),
      _at(hasRuns?352:185,actionY,178,31,
        _LegacyButton('Recent runs',historyDialog,color:const Color(0xff466baa))),
      if(state.error!=null && !state.error!.startsWith('Usage unavailable:'))
        _at(18,actionY+39,880,30,
        GestureDetector(onTap:()=>state.error=null,
          child:_label(state.error!,fontSize:12,color:const Color(0xff8a3121)))),
      if(state.error==null && state.repositoryWarning!=null)
        _at(18,actionY+39,880,30,Tooltip(
          message:state.repositoryWarning! +
            (state.repositoryAlternatives.isEmpty ? '' :
              '\\nOther checkout(s): '+state.repositoryAlternatives.join('; ')),
          child:_label(state.repositoryWarning!,fontSize:12,
            color:const Color(0xff8a3121)))),
    ];
    return _viewport(width:920,height:totalHeight,compact:false,children:children);
  }

  Widget _legacyRunGrid(List<Map<String,dynamic>> runs) => Container(
    decoration:BoxDecoration(color:Colors.white,border:Border.all(color:const Color(0xffb8c6d8))),
    child:Column(children:[
      SizedBox(height:31,child:Row(children:[
        _gridHead('Scheduled (local)',149),
        _gridHead('Time to run',205),
        _gridHead('Project',145),
        const Expanded(child:Padding(padding:EdgeInsets.only(left:5),
          child:Text('Model / access / instruction',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)))),
        _gridHead('Session',85),
      ])),
      Expanded(child:ListView.builder(
        key: const PageStorageKey<String>('upcoming-run-list'),
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemCount: runs.length,
        itemBuilder: (context, index) {
          final run = runs[index];
          return SizedBox(height:40,child:InkWell(
          onTap:()=>selectRun(stringField(run,'Name')),
          child:Container(
            color:selectedRun==stringField(run,'Name')?const Color(0xffd9e7f7):Colors.white,
            child:Row(children:[
              _gridCell(timeLabel(dateField(run,'When')),149),
              SizedBox(width:205,child:_parityCountdown(run)),
              _gridCell(stringField(run,'Repo').split(RegExp(r'[\\/]')).last,145),
              Expanded(child:Padding(padding:const EdgeInsets.only(left:5),
                child:Text(stringField(run,'Description'),maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:12)))),
              _gridCell(stringField(run,'Session').length>=8?
                stringField(run,'Session').substring(0,8):'—',85),
            ]),
          )));
        },
      )),
    ]),
  );

  Widget _gridHead(String text,double width)=>SizedBox(width:width,child:Padding(
    padding:const EdgeInsets.only(left:5,top:7),
    child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,
      style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold))));
  Widget _gridCell(String text,double width)=>SizedBox(width:width,child:Padding(
    padding:const EdgeInsets.only(left:5),
    child:Align(alignment:Alignment.centerLeft,
      child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,
        style:const TextStyle(fontSize:12)))));

  Widget _parityCountdown(Map<String,dynamic> run) {
    final working = stringField(run,'Status') == 'Running';
    final due = dateField(run,'When');
    final label = working ? 'Running' : countdown(due);
    final percent = working ? null :
      runElapsedPercent(due,field(run,'CreatedAt'))?.toDouble();
    const style = TextStyle(fontSize:11,fontWeight:FontWeight.bold);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text:label,style:style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final labelWidth = (painter.width + 8)
          .clamp(24.0, constraints.maxWidth * .52);
      painter.dispose();
      return Padding(padding:const EdgeInsets.symmetric(horizontal:6),
        child:Row(children:[
          SizedBox(width:labelWidth,child:Text(label,maxLines:1,style:style)),
          const SizedBox(width:5),
          Expanded(child:AeroLiquidBar(amount:percent,working:working,
            kind:working?'working':'time',appearance:controller!.appearance,height:15)),
        ]));
    });
  }

  Widget _compactParityView() {
    final state=controller!;
    final run=state.upcoming.isEmpty?null:state.upcoming.first;
    final top=run==null?65.0:246.0;
    final windows=state.quotaWindows.take(2).toList();
    final cardTop=top+34;
    final contentBottom=windows.isEmpty
      ? top+52
      : cardTop+windows.length*117+18;
    final totalHeight=math.max(166.0,contentBottom+40+
      (state.error!=null?31:0));
    final children=<Widget>[
      if(run!=null)...[
        _at(18,65,430,26,_label('Next run',fontSize:16,bold:true)),
        _at(18,91,428,129,_compactRunSurface(run)),
      ],
      if(windows.isEmpty)
        _at(18,top,428,28,_label(state.readingUsage
          ? 'Reading usage limits...' :
          state.error?.startsWith('Usage unavailable:')==true
            ? 'Usage unavailable; retrying automatically'
            : 'Usage limits unavailable',
          fontSize:13,color:const Color(0xff666666))),
      if(windows.isNotEmpty)...[
        _at(18,top,202,28,_label('Usage limits',fontSize:16,bold:true)),
        _at(225,top,219,28,Align(alignment:Alignment.centerRight,
          child:Text(state.quotaModel,maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontFamily:'Segoe UI',fontSize:12,color:Color(0xff666666))))),
        _at(18,cardTop,428,108,_usageSurface(windows.first,'Primary window','quota')),
        if(windows.length>1)_at(18,cardTop+117,428,108,
          _usageSurface(windows[1],'Secondary window','weekly')),
      ],
      _at(116,totalHeight-37,178,31,
        _LegacyButton('Recent runs',historyDialog,color:const Color(0xff466baa))),
      _at(306,totalHeight-37,140,31,
        _LegacyButton('Appearance...',appearanceDialog,color:const Color(0xff785ac5))),
      if(state.error!=null && !state.error!.startsWith('Usage unavailable:'))
        _at(18,totalHeight-71,428,25,
        _label(state.error!,fontSize:11,color:const Color(0xff8a3121))),
    ];
    return _viewport(width:464,height:totalHeight,compact:true,children:children);
  }

  Widget _compactRunSurface(Map<String,dynamic> run)=>Stack(children:[
    _at(0,0,428,129,const _LegacyBand(fill:Color(0xfff6f9fd),accent:Color(0xff516f98))),
    _at(14,9,220,28,_label(
      stringField(run,'Repo').split(RegExp(r'[\\/]')).last,fontSize:15,bold:true)),
    _at(252,9,159,28,Align(alignment:Alignment.centerRight,
      child:Text(stringField(run,'Status')=='Running'
        ? 'Running' : countdown(dateField(run,'When')),
        style:const TextStyle(color:Color(0xff168dff),fontSize:14,fontWeight:FontWeight.bold)))),
    _at(14,42,395,24,_label(stringField(run,'Description'),fontSize:12)),
    _at(14,70,395,23,_label('Scheduled '+_dateLabel(
      dateField(run,'When')??DateTime.now()),fontSize:12,color:const Color(0xff666666))),
    _at(14,101,396,17,_parityCountdown(run)),
  ]);

  Widget _viewport({required double width,required double height,
    required bool compact,required List<Widget> children}) {
    return ColoredBox(color:_legacyBackground,child:Align(
      alignment:Alignment.topLeft,
      child:SingleChildScrollView(
        scrollDirection:Axis.horizontal,
        child:SingleChildScrollView(scrollDirection:Axis.vertical,
          child:SizedBox(width:width,height:height,child:Stack(children:[
            ...children,
            _at(0,0,width,53,_parityHeader(compact:compact)),
          ]))),
      )));
  }

  Future<void> _browseRepo() async {
    try{
      final result=await controller!.adapter.call('browse');
      final path=stringField(result,'path');
      if(path.isEmpty)return;
      repository.text=path;
      controller!.edit(repository:path);
    }catch(error){toast('Folder picker: '+error.toString());}
  }

  Future<void> cancelSelected() async {
    final state=controller!;
    final matches=state.upcoming.where((r)=>
      stringField(r,'Name')==selectedRun &&
      stringField(r,'Status')=='Scheduled');
    if(matches.isEmpty){toast('Select a future scheduled run.');return;}
    // Selection is the user's explicit cancellation intent. The Windows
    // adapter still refuses cancellation after a task has started.
    try{
      final result=await state.cancel(selectedRun!);
      selectedRun=null;
      final warning=stringField(result,'warning');
      if(warning.isNotEmpty)toast('Cancelled with warning: '+warning);
    }on SchedulerOutcomeUncertain catch(error){
      toast(error.toString());
    }catch(error){toast('Cancellation failed: '+error.toString());}
  }
}

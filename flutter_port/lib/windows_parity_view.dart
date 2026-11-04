part of 'main.dart';

// Coordinates, band colors and labels follow CodexUiForms.ps1,
// CodexUiPixelTheme.ps1 and Update-DashboardLayout in CodexDashboard.ps1.
// Flutter owns interactivity; the existing worker owns scheduling policy.
const _legacyBackground = Color(0xfff0f5fb);
const _legacyInk = Color(0xff253a58);
const _legacyInput = Color(0xfffbfdff);

class _LegacyBand extends StatelessWidget {
  const _LegacyBand({required this.fill, required this.accent});
  final Color fill;
  final Color accent;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BandPainter(fill, accent),
    child: const SizedBox.expand(),
  );
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.fill, this.accent);
  final Color fill;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w < 18 || h < 18) return;
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color.lerp(fill, Colors.white, .30)!, fill],
    ).createShader(area));
    final border = Paint()..color = accent.withValues(alpha: .49)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(.5,.5,w-1,h-1),border);
    final top = Paint()..color = Colors.white.withValues(alpha: .73);
    final bottom = Paint()..color = accent.withValues(alpha: .26);
    canvas.drawLine(const Offset(5,2),Offset(w-16,2),top);
    canvas.drawLine(Offset(5,h-3),Offset(w-12,h-3),bottom);
    canvas.drawRect(Rect.fromLTWH(0,0,4,h),Paint()..color = accent);
    canvas.drawRect(const Rect.fromLTWH(8,0,13,2),Paint()..color=accent);
    canvas.drawRect(Rect.fromLTWH(w-10,2,6,4),Paint()..color=accent);
    final quiet = Paint()..color=accent.withValues(alpha: .31);
    canvas.drawRect(Rect.fromLTWH(w-15,7,5,4),quiet);
    for(double y=12;y<h-5;y+=22){
      canvas.drawRect(Rect.fromLTWH(0,y,4,5),Paint()..color=fill);
      canvas.drawRect(Rect.fromLTWH(5,y+1,3,3),quiet);
    }
    for(double x=27;x<w-20;x+=116){
      canvas.drawRect(Rect.fromLTWH(x,h-5,4,2),quiet);
      canvas.drawRect(Rect.fromLTWH(x+6,h-5,2,2),quiet);
    }
  }
  @override
  bool shouldRepaint(covariant _BandPainter old) => fill!=old.fill || accent!=old.accent;
}

class _LegacyButton extends StatelessWidget {
  const _LegacyButton(this.text, this.onPressed,{this.color=const Color(0xff516f98),this.primary=false});
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final enabled=onPressed!=null;
    final background=enabled ? color : const Color(0xffdde4ee);
    return Semantics(button: true, enabled: enabled, child: Material(
      color: background,
      child: InkWell(onTap: onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: enabled
              ? Color.lerp(color,Colors.black,.22)! : const Color(0xffb8c6d8)),
          child: Stack(children:[
            Positioned(left:4,right:4,top:2,
              child: Container(height:1,color:Colors.white.withValues(alpha: primary?.52:.28))),
            Positioned(right:4,top:5,
              child: Container(width:3,height:3,color:Colors.white.withValues(alpha:.35))),
            Center(child: Text(text,textAlign:TextAlign.center,
              style: TextStyle(color:enabled?Colors.white:const Color(0xff52647c),
                fontSize:13,fontWeight:primary?FontWeight.w700:FontWeight.w600))),
          ]),
        ))));
  }
}

class _LegacyInputBorder extends OutlineInputBorder {
  const _LegacyInputBorder()
    : super(borderSide: const BorderSide(color:Color(0xffb8c6d8)),
      borderRadius: BorderRadius.zero);
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
      {String? hint}) => TextField(
    controller:text,
    onChanged:change,
    maxLines:1,
    style:const TextStyle(fontFamily:'Segoe UI',fontSize:13,color:_legacyInk),
    decoration:InputDecoration(
      hintText:hint,isDense:true,filled:true,fillColor:_legacyInput,
      contentPadding:const EdgeInsets.symmetric(horizontal:7,vertical:5),
      enabledBorder:const _LegacyInputBorder(),
      focusedBorder:const OutlineInputBorder(borderRadius:BorderRadius.zero,
        borderSide:BorderSide(color:Color(0xff547fd2),width:1.3)),
    ));

  Widget _combo<T>({
    required String name,required T? selected,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  })=>Container(
    padding:const EdgeInsets.symmetric(horizontal:6),
    decoration:BoxDecoration(color:_legacyInput,
      border:Border.all(color:const Color(0xffb8c6d8))),
    child:DropdownButtonHideUnderline(child:DropdownButton<T>(
      key:ValueKey(name+':'+selected.toString()),
      value:selected,
      isExpanded:true,isDense:true,
      icon:const Icon(Icons.arrow_drop_down,size:19,color:_legacyInk),
      style:const TextStyle(fontFamily:'Segoe UI',fontSize:13,color:_legacyInk),
      items:items,onChanged:onChanged,
    )),
  );

  String _dateLabel(DateTime date,{bool long=false}) {
    const days=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    String d(int x)=>x.toString().padLeft(2,'0');
    final hour=date.hour%12==0?12:date.hour%12;
    if(long) return days[date.weekday-1]+' '+months[date.month-1]+' '+
      d(date.day)+', '+date.year.toString()+'  '+d(hour)+':'+d(date.minute)+
      (date.hour>=12?' PM':' AM');
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
      _at(12,72,400,24,_label(reset==null?'Reset time unavailable':
          'Resets '+_dateLabel(reset),fontSize:12,color:const Color(0xff666666))),
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

  Widget _fullParityView() {
    final state=controller!;
    final runs=state.upcoming;
    final hasRuns=runs.isNotEmpty;
    final extraRows=math.min(runs.length,4);
    final gridHeight=hasRuns?math.max(90.0,extraRows*40.0+35):0.0;
    final actionY=hasRuns?536+gridHeight+13:490.0;
    final totalHeight=hasRuns?actionY+77:566.0;
    final modelOptions=state.models.map((m)=>DropdownMenuItem<String>(
      value:stringField(m,'id'),
      child:Text(stringField(m,'name').isEmpty?stringField(m,'id'):stringField(m,'name'),
        maxLines:1,overflow:TextOverflow.ellipsis))).toList();
    final validModel=state.models.any((m)=>stringField(m,'id')==state.model);
    final effortOptions=state.efforts.map((e)=>DropdownMenuItem<String>(value:e,child:Text(e))).toList();
    final resetTime=field(state.quota,'recommendedResetAt');
    final reset=stringField(state.quota,'recommendationKind')=='exhausted-window' &&
      resetTime is num && resetTime>0
        ? nextWholeMinute(DateTime.fromMillisecondsSinceEpoch(
            resetTime.toInt()*1000).add(const Duration(minutes:2))):null;
    final children=<Widget>[
      _at(10,54,898,46,const _LegacyBand(fill:Color(0xffe8f1ff),accent:Color(0xff547fd2))),
      _at(10,102,898,44,const _LegacyBand(fill:Color(0xffe6f8f3),accent:Color(0xff168e87))),
      _at(10,148,898,44,const _LegacyBand(fill:Color(0xffedf3fa),accent:Color(0xff516f98))),
      _at(10,194,898,40,const _LegacyBand(fill:Color(0xfffff3e4),accent:Color(0xffc98737))),
      _at(10,238,898,71,const _LegacyBand(fill:Color(0xffe8f5fc),accent:Color(0xff2887b5))),
      _at(18,61,125,30,_label('Conversation')),
      _at(155,61,743,30,_combo<String>(
        name:'session',selected:state.sessions.any((m)=>stringField(m,'Id')==state.sessionId)?state.sessionId:null,
        items:state.sessions.map((m)=>DropdownMenuItem<String>(
          value:stringField(m,'Id'),child:Text(stringField(m,'Display'),
            maxLines:1,overflow:TextOverflow.ellipsis))).toList(),
        onChanged:(id){repository.clear();state.selectSession(id);})),
      _at(18,108,132,30,_label('Repository root')),
      _at(155,108,605,30,_textbox(repository,(v)=>state.edit(repository:v))),
      _at(773,106,125,31,_LegacyButton('Browse',_browseRepo,color:const Color(0xff168e87))),
      _at(18,154,132,30,_label('Run at (local)')),
      _at(155,154,38,30,_LegacyButton('−',()=>state.edit(time:stepRunAt(state.runAt,-1)))),
      _at(202,154,237,30,_LegacyButton(_dateLabel(state.runAt,long:true),pickTime,
        color:const Color(0xff516f98))),
      _at(446,154,38,30,_LegacyButton('+',()=>state.edit(time:stepRunAt(state.runAt,1)))),
      _at(637,154,112,30,_LegacyButton('Now +2',()=>state.edit(time:suggestedRunAt()))),
      _at(761,154,137,30,_LegacyButton('Reset +2',
        reset==null?null:()=>state.edit(time:reset))),
      _at(18,199,64,30,_label('Model')),
      _at(90,199,258,30,_combo<String>(name:'model',
        selected:validModel?state.model:null,
        items:modelOptions,onChanged:state.selectModel)),
      _at(361,199,86,30,_label('Reasoning')),
      _at(450,199,122,30,_combo<String>(name:'effort',
        selected:state.efforts.contains(state.effort)?state.effort:null,
        items:effortOptions,onChanged:(s){if(s!=null)state.edit(reasoning:s);})),
      _at(586,199,60,30,_label('Access')),
      _at(652,199,246,30,_combo<String>(name:'access',selected:state.access,
        items:const[
          DropdownMenuItem(value:'workspace-write',child:Text('Workspace write')),
          DropdownMenuItem(value:'yolo',child:Text('Full access (YOLO)')),
          DropdownMenuItem(value:'read-only',child:Text('Read-only test')),
        ],onChanged:(s){if(s!=null)state.edit(accessMode:s);})),
      _at(18,243,128,30,_label('Instruction')),
      _at(155,243,743,30,_textbox(instruction,(v)=>state.edit(instruction:v))),
      _at(720,274,178,31,_LegacyButton('Schedule once',
        state.canSchedule?schedule:null,color:const Color(0xff2277a1),primary:true)),
      _at(18,309,880,2,Container(color:const Color(0xffc6d2e3))),
      _at(18,322,300,30,_label('Usage remaining',fontSize:16,bold:true)),
      _at(18,358,428,108,_usageSurface(state.quotaWindows.isNotEmpty?state.quotaWindows.first:null,
        'Primary window','quota')),
      _at(470,358,428,108,_usageSurface(state.quotaWindows.length>1?state.quotaWindows[1]:null,
        'Secondary window','weekly')),
      if(hasRuns)...[
        _at(18,485,880,2,Container(color:const Color(0xffc6d2e3))),
        _at(18,499,400,30,_label('Upcoming runs',fontSize:16,bold:true)),
        _at(18,536,880,gridHeight,_legacyRunGrid(runs)),
        _at(18,actionY,154,31,_LegacyButton('Cancel selected',
          selectedRun!=null && !state.busy?cancelSelected:null,color:const Color(0xffb86265))),
      ],
      _at(hasRuns?185:18,actionY,154,31,
        _LegacyButton('Open logs folder',openLogs,color:const Color(0xff52749b))),
      _at(hasRuns?352:185,actionY,178,31,
        _LegacyButton('Recent runs',historyDialog,color:const Color(0xff466baa))),
      if(state.error!=null) _at(18,actionY+39,880,30,
        GestureDetector(onTap:()=>state.error=null,
          child:_label(state.error!,fontSize:12,color:const Color(0xff8a3121)))),
    ];
    return _viewport(width:920,height:totalHeight,compact:false,children:children);
  }

  List<Map<String,dynamic>> get _noMoreThanFour => controller!.upcoming.take(4).toList();

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
      for(final run in _noMoreThanFour)
        SizedBox(height:40,child:InkWell(
          onTap:()=>setState(()=>selectedRun=stringField(run,'Name')),
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
          ))),
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
    final status=stringField(run,'Status');
    final due=dateField(run,'When');
    final created=field(run,'CreatedAt');
    final working=status=='Running';
    double? percent;
    if(!working&&due!=null&&created is num){
      final start=DateTime.fromMillisecondsSinceEpoch(created.toInt()*1000);
      final total=due.difference(start).inMilliseconds;
      if(total>0)percent=100*DateTime.now().difference(start).inMilliseconds/total;
    }
    return Padding(padding:const EdgeInsets.symmetric(horizontal:6),
      child:Row(children:[
        SizedBox(width:64,child:Text(working?'Running':countdown(due),
          style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold))),
        const SizedBox(width:5),
        Expanded(child:AeroLiquidBar(amount:percent,working:working,
          kind:working?'working':'time',appearance:controller!.appearance,height:15)),
      ]));
  }

  Widget _compactParityView() {
    final state=controller!;
    final run=state.upcoming.isEmpty?null:state.upcoming.first;
    final hasRun=run!=null;
    final top=hasRun?246.0:65.0;
    final cardTop=top+34;
    final visibleCount=state.quotaWindows.isEmpty?1:math.min(2,state.quotaWindows.length);
    final totalHeight=cardTop+visibleCount*117+58;
    final children=<Widget>[
      if(run!=null)...[
        _at(18,65,430,26,_label('Next run',fontSize:16,bold:true)),
        _at(18,91,428,129,_compactRunSurface(run)),
      ],
      _at(18,top,202,28,_label('Usage limits',fontSize:16,bold:true)),
      _at(225,top,219,28,Align(alignment:Alignment.centerRight,
        child:Text(state.quotaModel,maxLines:1,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontFamily:'Segoe UI',fontSize:12,color:Color(0xff666666))))),
      _at(18,cardTop,428,108,_usageSurface(
        state.quotaWindows.isNotEmpty?state.quotaWindows.first:null,
        'Primary window','quota')),
      if(visibleCount>1)_at(18,cardTop+117,428,108,
        _usageSurface(state.quotaWindows[1],'Secondary window','weekly')),
      _at(116,totalHeight-37,178,31,
        _LegacyButton('Recent runs',historyDialog,color:const Color(0xff466baa))),
      _at(306,totalHeight-37,140,31,
        _LegacyButton('Appearance...',appearanceDialog,color:const Color(0xff52749b))),
      if(state.error!=null)_at(18,totalHeight-71,428,25,
        _label(state.error!,fontSize:11,color:const Color(0xff8a3121))),
    ];
    return _viewport(width:464,height:totalHeight,compact:true,children:children);
  }

  Widget _compactRunSurface(Map<String,dynamic> run)=>Stack(children:[
    _at(0,0,428,129,const _LegacyBand(fill:Color(0xfff6f9fd),accent:Color(0xff516f98))),
    _at(14,9,220,28,_label(
      stringField(run,'Repo').split(RegExp(r'[\\/]')).last,fontSize:15,bold:true)),
    _at(252,9,159,28,Align(alignment:Alignment.centerRight,
      child:Text(countdown(dateField(run,'When')),
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
    if(!await confirm('Cancel selected','Cancel this task in Windows Task Scheduler?'))return;
    try{
      final result=await state.cancel(selectedRun!);
      selectedRun=null;
      final warning=stringField(result,'warning');
      if(warning.isNotEmpty)toast('Cancelled with warning: '+warning);
    }catch(error){toast('Cancellation failed: '+error.toString());}
  }
}

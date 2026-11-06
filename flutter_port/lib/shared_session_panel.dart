part of 'main.dart';

/// Mirrors one App Server owner; no new conversation process is launched.
class SharedSessionPanel extends StatefulWidget {
  const SharedSessionPanel({super.key, required this.controller, required this.name});
  final SchedulerController controller;
  final String name;
  @override
  State<SharedSessionPanel> createState() => _SharedSessionPanelState();
}

class _SharedSessionPanelState extends State<SharedSessionPanel> {
  Map<String, dynamic>? snapshot;
  final Map<String, String> answers = {};
  Timer? timer;
  bool reading = false, sending = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_read()));
  }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> _read() async {
    if (!mounted || reading) return;
    reading = true;
    try {
      final data = await widget.controller.readSharedSession(widget.name);
      if (!mounted) return;
      setState(() { snapshot = data; problem = null; });
      if (const ['completed','failed','interrupted'].contains(stringField(data,'status'))) timer?.cancel();
    } catch (e) {
      if (mounted) setState(() => problem = e.toString());
    } finally { reading = false; }
  }

  Future<void> _answer(String id, Map<String, dynamic> payload) async {
    if (sending) return;
    setState(() { sending = true; problem = null; });
    try {
      await widget.controller.replySharedSession(widget.name, id, payload);
      answers.clear();
      await _read();
    } catch (e) {
      if (mounted) setState(() => problem = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Widget _request(Map<String, dynamic> request) {
    final id = stringField(request,'id');
    final method = stringField(request,'method');
    final params = field(request,'params');
    if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('APPROVAL REQUESTED',style: TextStyle(color: DeckColor.gold,
          fontWeight: FontWeight.w800)),
        Text(stringField(params,'reason'),style: const TextStyle(color: DeckColor.text)),
        SelectableText(stringField(params,'command'),style:
          const TextStyle(color: DeckColor.text,fontFamily:'Consolas')),
        Wrap(spacing: 8,children: [
          OutlinedButton(key: Key('shared-decline-' + id),
            onPressed: sending ? null : () => _answer(id,{'decision':'decline'}),
            child: const Text('Decline')),
          FilledButton(key: Key('shared-approve-' + id),
            onPressed: sending ? null : () => _answer(id,{'decision':'accept'}),
            child: const Text('Approve once')),
        ]),
      ]);
    }
    if (method == 'item/tool/requestUserInput') {
      final questions = recordList(field(params,'questions'));
      final complete = questions.isNotEmpty && questions.every(
        (q) => (answers[stringField(q,'id')] ?? '').isNotEmpty);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CODEX HAS A QUESTION',style: TextStyle(
          color: DeckColor.gold,fontWeight:FontWeight.w800)),
        for (final question in questions) ...[
          Padding(padding: const EdgeInsets.only(top: 10,bottom: 6),
            child: Text(stringField(question,'question'),
              style: const TextStyle(color: DeckColor.text))),
          Wrap(spacing: 6,runSpacing: 4,children: [
            for (final option in recordList(field(question,'options')))
              ChoiceChip(
                label: Text(stringField(option,'label')),
                selected: answers[stringField(question,'id')] ==
                  stringField(option,'label'),
                onSelected: sending ? null : (_) => setState(() {
                  answers[stringField(question,'id')] =
                    stringField(option,'label');
                }),
              ),
          ]),
          TextField(
            key: Key('shared-answer-' + stringField(question,'id')),
            obscureText: field(question,'isSecret') == true,
            decoration: const InputDecoration(hintText:'Or enter an answer'),
            onChanged: (text) => setState(() {
              answers[stringField(question,'id')] =
                text.trim().isEmpty ? '' : 'user_note: ' + text.trim();
            }),
          ),
        ],
        const SizedBox(height: 10),
        FilledButton(key: Key('shared-submit-' + id),
          onPressed: sending || !complete ? null : () {
            final values = <String,dynamic>{};
            for (final q in questions) {
              final key = stringField(q,'id');
              values[key] = {'answers':[answers[key]]};
            }
            _answer(id,{'answers':values});
          },child:const Text('Send answers')),
      ]);
    }
    return Text('Codex needs input: ' + method +
      '. This request type cannot be approved in this preview.',
      style: const TextStyle(color: DeckColor.gold));
  }

  @override
  Widget build(BuildContext context) {
    final status = stringField(snapshot,'status');
    final requests = recordList(field(snapshot,'pending'));
    final events = recordList(field(snapshot,'events'));
    final text = events.where((e) => stringField(e,'kind') == 'text')
      .map((e) => stringField(e,'text')).join();
    return ListView(
      key: const Key('shared-session-panel'),
      padding: const EdgeInsets.all(15),
      children: [
        Text(status == 'needs-input' ? 'Codex is waiting for you'
          : status.isEmpty ? 'Connecting to Codex…' : 'Codex: ' + status,
          style: TextStyle(color: status == 'needs-input'
            ? DeckColor.gold : DeckColor.aqua,
            fontSize: 14,fontWeight: FontWeight.w800)),
        if (problem != null) Text(problem!,
          style: const TextStyle(color: DeckColor.rose)),
        const SizedBox(height: 12),
        for (final request in requests)
          Container(margin:const EdgeInsets.only(bottom:12),
            padding:const EdgeInsets.all(12),
            decoration:BoxDecoration(
              color:const Color(0xff232b40),
              border:Border.all(color:DeckColor.gold.withValues(alpha:.4)),
              borderRadius:BorderRadius.circular(12)),
            child:_request(request)),
        const Text('LIVE CONVERSATION',style:TextStyle(
          color:DeckColor.muted,fontSize:10,fontWeight:FontWeight.w800)),
        const SizedBox(height: 6),
        SelectableText(text.isEmpty
          ? 'Waiting for Codex output. Questions appear above.'
          : text.substring(math.max(0,text.length-6000)),
          style:const TextStyle(color:DeckColor.text,
            fontFamily:'Consolas',fontSize:12,height:1.4)),
      ],
    );
  }
}

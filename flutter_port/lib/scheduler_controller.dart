import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bridge.dart';

/// Owns scheduler state; Flutter widgets only render it and forward intent.
/// All privileged actions are revalidated inside the existing PowerShell worker.
class SchedulerController extends ChangeNotifier {
  SchedulerController(this.adapter);
  final SchedulerAdapter adapter;

  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> runs = [];
  List<Map<String, dynamic>> history = [];
  List<Map<String, dynamic>> models = [];
  Map<String, dynamic>? quota;
  String logDirectory = '';
  String? error;
  String? sessionId;
  String? model;
  String? effort;
  String repo = '';
  String message = 'Resume.';
  String access = 'workspace-write';
  bool compact = false;
  bool ready = false;
  bool busy = false;
  bool readingUsage = false;
  bool _usageQueued = false;
  bool editedTime = false;
  DateTime runAt = suggestedRunAt();
  DateTime? quotaAt;
  String quotaModel = '';
  int _selectionEpoch = 0;
  Timer? _statusTimer;
  Timer? _refreshTimer;
  Timer? _clockTimer;
  Timer? _saveTimer;
  bool _polling = false;
  bool _loading = false;
  bool _disposed = false;

  List<Map<String, dynamic>> get upcoming =>
    runs.where((r) => const ['Scheduled', 'Running'].contains(stringField(r, 'Status'))).toList();

  List<String> get efforts {
    final selected = models.where((m) => stringField(m, 'id') == model);
    if (selected.isEmpty) return [];
    final raw = field(selected.first, 'efforts');
    return raw is List ? raw.whereType<String>().where((v) => v != 'ultra').toList() : [];
  }

  bool get canSchedule {
    if (busy || readingUsage || quota == null || quotaAt == null ||
        DateTime.now().difference(quotaAt!).inSeconds > 120 ||
        model == null || sessionId == null || !efforts.contains(effort) ||
        quotaModel != model || field(quota, 'ordinaryUsageAllowed') == false) return false;
    return RegExp(r'^workspace-sha256:[a-f0-9]{64}$')
      .hasMatch(stringField(quota, 'accountId'));
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    await load(initial: true);
    if (_disposed) return;
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => load());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!editedTime && runAt.isBefore(earliestRunAt())) runAt = suggestedRunAt();
      _changed();
    });
  }

  Future<void> load({bool initial = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await adapter.call('load');
      if (_disposed) return;
      sessions = recordList(field(data, 'sessions'));
      runs = recordList(field(data, 'pending'));
      history = recordList(field(data, 'history'));
      logDirectory = stringField(data, 'logDirectory');
      if (initial) {
        final settingsData = field(data, 'settings');
        final settings = settingsData is Map ? Map<String, dynamic>.from(settingsData) : <String, dynamic>{};
        final draftData = field(settings, 'draft');
        final draft = draftData is Map ? Map<String, dynamic>.from(draftData) : <String, dynamic>{};
        sessionId = stringField(draft, 'sessionId').isEmpty ? null : stringField(draft, 'sessionId');
        if (!sessions.any((s) => stringField(s, 'Id') == sessionId)) sessionId = null;
        model = stringField(draft, 'model').isEmpty ? null : stringField(draft, 'model');
        effort = stringField(draft, 'effort').isEmpty ? null : stringField(draft, 'effort');
        repo = stringField(draft, 'repo');
        message = stringField(draft, 'message').isEmpty ? 'Resume.' : stringField(draft, 'message');
        final preferredAccess = stringField(draft, 'access');
        access = const ['workspace-write', 'read-only', 'yolo'].contains(preferredAccess)
          ? preferredAccess : 'workspace-write';
        compact = field(settings, 'compactMode') == true;
        final savedTime = DateTime.tryParse(stringField(draft, 'runAt'));
        if (savedTime != null && savedTime.isAfter(earliestRunAt())) {
          runAt = savedTime; editedTime = true;
        }
        final colors = field(settings, 'flutterAppearance');
        if (colors is Map) {
          for (final e in colors.entries) {
            if (e.value is num) appearance[e.key.toString()] = (e.value as num).toInt();
          }
        }
        ready = true;
      }
      error = null;
      _changed();
      await readUsage();
    } catch (e) {
      error = 'Refresh failed: $e';
      _changed();
    } finally {
      _loading = false;
    }
  }

  Future<void> poll() async {
    if (_polling || _loading) return;
    _polling = true;
    try {
      final data = await adapter.call('pending');
      if (_disposed) return;
      runs = recordList(field(data, 'pending'));
      history = recordList(field(data, 'history'));
      _changed();
    } catch (e) {
      error = 'Task refresh failed: $e';
      _changed();
    } finally {
      _polling = false;
    }
  }

  Future<void> readUsage() async {
    if (readingUsage) {
      _usageQueued = true;
      return;
    }
    readingUsage = true;
    _changed();
    final requested = model ?? '';
    try {
      final data = await adapter.call('usage', requested.isEmpty ? {} : {'model': requested});
      if (_disposed) return;
      quota = data;
      models = recordList(field(data, 'models'));
      quotaAt = DateTime.now();
      final candidates = models.map((m) => stringField(m, 'id'));
      if (model == null || !candidates.contains(model)) {
        final defaults = models.where((m) => field(m, 'isDefault') == true);
        model = defaults.isNotEmpty ? stringField(defaults.first, 'id') :
          (models.isEmpty ? null : stringField(models.first, 'id'));
      }
      final available = efforts;
      if (!available.contains(effort)) {
        final selected = models.where((m) => stringField(m, 'id') == model);
        final preferred = selected.isEmpty ? '' : stringField(selected.first, 'defaultEffort');
        effort = available.contains(preferred) ? preferred :
          (available.isEmpty ? null : available.first);
      }
      quotaModel = requested.isEmpty ? stringField(data, 'model') : requested;
      error = null;
    } catch (e) {
      quota = null; quotaAt = null; quotaModel = '';
      error = 'Usage unavailable: $e';
    } finally {
      readingUsage = false;
      _changed();
      if (_usageQueued && !_disposed) {
        _usageQueued = false;
        unawaited(readUsage());
      }
    }
  }

  void edit({
    String? repository, String? instruction, String? accessMode,
    String? reasoning, bool? compactMode, DateTime? time,
  }) {
    if (repository != null) repo = repository;
    if (instruction != null) message = instruction;
    if (accessMode != null) access = accessMode;
    if (reasoning != null) effort = reasoning;
    if (compactMode != null) compact = compactMode;
    if (time != null) { runAt = time; editedTime = true; }
    _changed();
    _queueSave();
  }

  void selectModel(String? id) {
    if (model == id) return;
    model = id; effort = null; quota = null; quotaAt = null;
    _changed(); _queueSave(); readUsage();
  }

  Future<void> selectSession(String? id) async {
    if (id == sessionId) return;
    final generation = ++_selectionEpoch;
    sessionId = id; repo = '';
    _changed(); _queueSave();
    if (id == null) return;
    try {
      final result = await adapter.call('select', {'sessionId': id});
      if (generation != _selectionEpoch || sessionId != id) return;
      final f = field(result, 'found');
      final found = f is Map ? Map<String, dynamic>.from(f) : null;
      if (repo.trim().isEmpty) repo = stringField(found, 'Root');
      final associated = stringField(result, 'model');
      if (models.any((m) => stringField(m, 'id') == associated)) selectModel(associated);
      _changed();
    } catch (e) {
      error = 'Repository lookup: $e';
      _changed();
    }
  }

  final Map<String, int> appearance = {
    'quota': 0xff5baf92, 'time': 0xff467dc0, 'working': 0xff518d9f,
  };
  void setAppearance(Map<String, int> replacement) {
    appearance.addAll(replacement);
    _changed(); _queueSave();
  }

  void _queueSave() {
    if (!ready) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), () => save());
  }

  Future<void> save() async {
    if (!ready) return;
    try {
      await adapter.call('save', {
        'compactMode': compact,
        'flutterAppearance': appearance,
        'draft': {
          'sessionId': sessionId ?? '', 'repo': repo, 'model': model ?? '',
          'effort': effort ?? '', 'access': access, 'message': message,
          'runAt': localIsoMinute(runAt),
        },
      });
    } catch (e) {
      error = 'Preferences were not saved: $e';
      _changed();
    }
  }

  Future<String> schedule({required bool confirmUnrestricted, required bool confirmOverlap}) async {
    if (!canSchedule) throw SchedulerException('Fresh quota and verified workspace required.');
    busy = true; _changed();
    try {
      final response = await adapter.call('schedule', {
        'sessionId': sessionId, 'repo': repo, 'model': model, 'effort': effort,
        'access': access, 'message': message.trim(), 'runAt': localIsoMinute(runAt),
        'confirmUnrestricted': confirmUnrestricted, 'confirmOverlap': confirmOverlap,
      });
      // Once Windows has registered the task, never report a later preferences
      // failure as a failed registration.
      await save();
      await poll();
      return stringField(response, 'name');
    } catch (_) {
      await poll();
      rethrow;
    } finally {
      busy = false; _changed();
    }
  }

  Future<Map<String, dynamic>> cancel(String name) async {
    busy = true; _changed();
    try {
      return await adapter.call('cancel', {'name': name});
    } finally {
      await poll();
      busy = false; _changed();
    }
  }

  Future<Map<String, dynamic>> evidence(String name) => adapter.call('evidence', {'name': name});
  Future<void> hide(String name) async {
    await adapter.call('hide', {'name': name});
    await poll();
  }

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}

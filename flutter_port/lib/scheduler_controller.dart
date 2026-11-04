import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bridge.dart';
import 'aero_appearance.dart';

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
  AeroAppearance appearance = AeroAppearance.defaults;
  String? repositoryWarning;
  List<String> repositoryAlternatives = [];
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
  int _repositoryEditEpoch = 0;
  Future<void>? _repositoryLookup;
  String? _lookupSessionId;
  bool _keepRestoredModel = false;
  Timer? _statusTimer;
  Timer? _refreshTimer;
  Timer? _clockTimer;
  Timer? _saveTimer;
  Future<void> _saveTail = Future<void>.value();
  bool _polling = false;
  bool _loading = false;
  bool _disposed = false;
  bool _saveFailed = false;
  DateTime? _lastFullRefresh;

  List<Map<String, dynamic>> get quotaWindows => recordList(field(quota, 'windows'));

  /// Reset +1 is offered only for a fresh recommendation for this model.
  /// Expired or ambiguous quota data must not suggest an inaccurate reset.
  DateTime? get resetSuggestion {
    if (readingUsage || quotaAt == null || quotaModel != model ||
        DateTime.now().difference(quotaAt!).inSeconds > 120 ||
        stringField(quota, 'catalogError').isNotEmpty) {
      return null;
    }
    return recommendedResetRunAt(quota);
  }

  List<Map<String, dynamic>> get upcoming =>
    runs.where((r) => const ['Scheduled', 'Running'].contains(stringField(r, 'Status'))).toList();

  List<String> get efforts {
    final selected = models.where((m) => stringField(m, 'id') == model);
    if (selected.isEmpty) return [];
    final raw = field(selected.first, 'efforts');
    return raw is List ? raw.whereType<String>().where((v) => v != 'ultra').toList() : [];
  }

  String get usageTargetModel {
    if (compact && upcoming.isNotEmpty) {
      final runModel = stringField(upcoming.first, 'Model');
      if (RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$').hasMatch(runModel)) {
        return runModel;
      }
    }
    return model ?? '';
  }

  /// Quota exhaustion now does not forbid scheduling a later run. As with
  /// WinForms v1.16, the pinned worker rechecks quota at execution time.
  bool get canSchedule {
    if (compact || busy || readingUsage || quota == null || quotaAt == null ||
        DateTime.now().difference(quotaAt!).inSeconds > 120 ||
        model == null || sessionId == null || !efforts.contains(effort) ||
        quotaModel != model || stringField(quota, 'catalogError').isNotEmpty) return false;
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
    _lastFullRefresh = DateTime.now();
    try {
      final data = await adapter.call('load');
      if (_disposed) return;
      sessions = recordList(field(data, 'sessions'));
      runs = recordList(field(data, 'pending'));
      history = recordList(field(data, 'history'));
      logDirectory = stringField(data, 'logDirectory');
      // WinForms picks the most recent session when its saved choice is gone
      // and immediately looks up the selected conversation's Git root.
      if (initial || !ready) {
        final settingsData = field(data, 'settings');
        final settings = settingsData is Map ? Map<String, dynamic>.from(settingsData) : <String, dynamic>{};
        final draftData = field(settings, 'draft');
        final draft = draftData is Map ? Map<String, dynamic>.from(draftData) : <String, dynamic>{};
        final savedId = stringField(draft, 'sessionId');
        final savedChoiceExists = sessions.any((s) => stringField(s, 'Id') == savedId);
        sessionId = savedChoiceExists ? savedId : _firstSessionId();
        // Never pair an unrelated fallback session with the old session's root.
        repo = savedChoiceExists ? stringField(draft, 'repo') : '';
        model = stringField(draft, 'model').isEmpty ? null : stringField(draft, 'model');
        effort = stringField(draft, 'effort').isEmpty ? null : stringField(draft, 'effort');
        _keepRestoredModel = savedChoiceExists && model != null;
        message = stringField(draft, 'message').isEmpty ? 'Resume.' : stringField(draft, 'message');
        final preferredAccess = stringField(draft, 'access');
        access = const ['workspace-write', 'read-only', 'yolo'].contains(preferredAccess)
          ? preferredAccess : 'workspace-write';
        compact = field(settings, 'compactMode') == true;
        final savedTime = DateTime.tryParse(stringField(draft, 'runAt'));
        if (savedTime != null && savedTime.isAfter(earliestRunAt())) {
          runAt = savedTime; editedTime = true;
        }
        appearance = AeroAppearance.fromJson(field(settings, 'barAppearance'));
        ++_selectionEpoch;
        ready = true;
      } else if (sessionId == null ||
          !sessions.any((s) => stringField(s, 'Id') == sessionId)) {
        ++_selectionEpoch;
        sessionId = _firstSessionId();
        repo = '';
        repositoryWarning = null;
        repositoryAlternatives = [];
        _keepRestoredModel = false;
        _queueSave();
      }
      error = null;
      _changed();
      // A refresh may heal an unresolved repository. Coalesce overlapping
      // lookups; never block quota refresh or discard a manually chosen root.
      unawaited(_ensureRepositoryLookup());
      await readUsage();
    } catch (e) {
      error = 'Refresh failed: $e';
      _changed();
    } finally {
      _loading = false;
    }
  }

  /// WinForms refreshes immediately on focus after 15 seconds away.
  /// The periodic refresh remains the fallback while the window is idle.
  Future<void> refreshOnFocus([DateTime? now]) async {
    if (_loading || _disposed) return;
    final current = now ?? DateTime.now();
    if (_lastFullRefresh == null ||
        current.difference(_lastFullRefresh!) >= const Duration(seconds: 15)) {
      await load();
    }
  }

  Future<void> poll() async {
    if (_polling || _loading) return;
    _polling = true;
    try {
      final data = await adapter.call('pending');
      if (_disposed) return;
      final previousTarget = usageTargetModel;
      runs = recordList(field(data, 'pending'));
      history = recordList(field(data, 'history'));
      if (usageTargetModel != previousTarget) {
        quota = null; quotaAt = null; quotaModel = '';
        unawaited(readUsage());
      }
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
    final requested = usageTargetModel;
    try {
      final data = await adapter.call('usage', requested.isEmpty ? {} : {'model': requested});
      if (_disposed) return;
      if (stringField(data, 'catalogError').isNotEmpty) {
        throw SchedulerException('Model catalog: ' + stringField(data, 'catalogError'));
      }
      final liveModels = recordList(field(data, 'models'));
      if (liveModels.isEmpty) throw SchedulerException('Codex returned no supported models.');
      models = liveModels;
      if (model == null || !models.any((m) => stringField(m, 'id') == model)) {
        final preferred = models.where((m) => field(m, 'isDefault') == true);
        model = stringField(preferred.isNotEmpty ? preferred.first : models.first, 'id');
      }
      final available = efforts;
      if (!available.contains(effort)) {
        final selected = models.where((m) => stringField(m, 'id') == model);
        final defaultEffort = selected.isEmpty ? '' : stringField(selected.first, 'defaultEffort');
        effort = available.contains(defaultEffort) ? defaultEffort :
          (available.isEmpty ? null : available.first);
      }
      quota = data;
      quotaAt = DateTime.now();
      quotaModel = requested.isEmpty ? stringField(data, 'model') : requested;
      if (usageTargetModel != quotaModel) _usageQueued = true;
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
    if (repository != null) {
      ++_repositoryEditEpoch;
      repo = repository;
      repositoryWarning = null;
      repositoryAlternatives = [];
    }
    if (instruction != null) message = instruction;
    if (accessMode != null) access = accessMode;
    if (reasoning != null) effort = reasoning;
    if (compactMode != null && compact != compactMode) {
      compact = compactMode;
      quota = null; quotaAt = null; quotaModel = '';
      unawaited(readUsage());
    }
    if (time != null) { runAt = time; editedTime = true; }
    _changed();
    _queueSave();
  }

  void selectModel(String? id) {
    if (model == id) return;
    model = id; effort = null; quota = null; quotaAt = null;
    _changed(); _queueSave(); readUsage();
  }

  String? _firstSessionId() =>
      sessions.isEmpty ? null : stringField(sessions.first, 'Id');

  Future<void> selectSession(String? id) async {
    if (id != sessionId) {
      ++_selectionEpoch;
      sessionId = id;
      repo = '';
      repositoryWarning = null;
      repositoryAlternatives = [];
      _keepRestoredModel = false;
      _changed();
      _queueSave();
    }
    await _ensureRepositoryLookup();
  }

  /// A selected session is resolved on startup, after switching sessions,
  /// and on refresh if earlier discovery found nothing. The original
  /// CodexData reader supplies Git evidence; Flutter never guesses a path.
  Future<void> _ensureRepositoryLookup() async {
    final id = sessionId;
    if (_disposed || id == null || repo.trim().isNotEmpty ||
        !sessions.any((s) => stringField(s, 'Id') == id)) return;
    if (_lookupSessionId == id && _repositoryLookup != null) {
      await _repositoryLookup;
      return;
    }
    final selection = _selectionEpoch;
    final edited = _repositoryEditEpoch;
    final modelBeforeLookup = model;
    final request = _resolveRepository(id, selection, edited, modelBeforeLookup);
    _repositoryLookup = request;
    _lookupSessionId = id;
    try {
      await request;
    } finally {
      if (identical(request, _repositoryLookup)) {
        _repositoryLookup = null;
        _lookupSessionId = null;
      }
    }
  }

  Future<void> _resolveRepository(String id, int selection, int edited,
      String? modelBeforeLookup) async {
    try {
      final result = await adapter.call('select', {'sessionId': id});
      if (_disposed || selection != _selectionEpoch || sessionId != id) return;
      // A manual Browse or text edit wins even if the user cleared the field.
      if (edited == _repositoryEditEpoch && repo.trim().isEmpty) {
        final source = field(result, 'found');
        final found = source is Map ? Map<String, dynamic>.from(source) : null;
        repo = stringField(found, 'Root');
        final alternatives = field(found, 'AlternativeRoots');
        final candidates = field(found, 'Candidates');
        repositoryAlternatives = alternatives is List
          ? alternatives.whereType<String>().toList()
          : [];
        if (repo.isEmpty && candidates is List && candidates.length > 1) {
          repositoryAlternatives = candidates.whereType<String>().toList();
        }
        repositoryWarning = repositoryAlternatives.isNotEmpty
          ? repo.isEmpty
            ? 'Conflicting checkouts: choose Browse to select the active repository.'
            : 'Other checkouts found: verify the selected repository.'
          : repo.isEmpty ? 'Repository unresolved; use Browse.' : null;
        _queueSave();
      }
      // WinForms preserves a model explicitly restored for the same session.
      final associated = stringField(result, 'model');
      if (!_keepRestoredModel && model == modelBeforeLookup &&
          models.any((m) => stringField(m, 'id') == associated)) {
        selectModel(associated);
      }
      _changed();
    } catch (e) {
      if (_disposed || selection != _selectionEpoch || sessionId != id) return;
      repositoryWarning = 'Repository lookup unavailable; retrying automatically.';
      error = 'Repository lookup: $e';
      _changed();
    }
  }

  void updateAppearance(AeroAppearance value) {
    if (appearance == value) return;
    appearance = value;
    _changed();
    _queueSave();
  }

  /// Closing the window must not discard edits made during the debounce.
  /// Return false if storage rejected the write so the window can remain open.
  Future<bool> flushPreferences() async {
    _saveTimer?.cancel();
    await save();
    return !_saveFailed;
  }

  void _queueSave() {
    if (!ready) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), () => save());
  }

  /// Serialize writes: a slow, earlier save must never overwrite a newer
  /// draft or accepted appearance after the newer write has completed.
  Future<void> save() {
    if (!ready || _disposed) return Future<void>.value();
    final snapshot = <String, dynamic>{
      'compactMode': compact,
      'barAppearance': appearance.toJson(),
      'draft': {
        'sessionId': sessionId ?? '', 'repo': repo, 'model': model ?? '',
        'effort': effort ?? '', 'access': access, 'message': message,
        'runAt': localIsoSecond(runAt),
      },
    };
    _saveTail = _saveTail.then((_) async {
      if (_disposed) return;
      try {
        await adapter.call('save', snapshot);
        _saveFailed = false;
        if (error?.startsWith('Preferences save could not be confirmed:') == true) {
          error = null;
          _changed();
        }
      } catch (e) {
        _saveFailed = true;
        error = 'Preferences save could not be confirmed: $e';
        _changed();
      }
    });
    return _saveTail;
  }

  Future<String> schedule({required bool confirmUnrestricted, required bool confirmOverlap}) async {
    if (!canSchedule) throw SchedulerException('Fresh quota and verified workspace required.');
    busy = true; _changed();
    try {
      final response = await adapter.call('schedule', {
        'sessionId': sessionId, 'repo': repo, 'model': model, 'effort': effort,
        'access': access, 'message': message.trim(), 'runAt': localIsoSecond(runAt),
        'confirmUnrestricted': confirmUnrestricted, 'confirmOverlap': confirmOverlap,
      });
      // Once Windows has registered the task, never report a later preferences
      // failure as a failed registration.
      await save();
      await poll();
      // Like the WinForms coordinator, refresh catalog/quota and sessions
      // after registration without holding the success response hostage.
      unawaited(load());
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
      unawaited(load());
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

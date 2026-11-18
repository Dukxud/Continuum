import 'dart:async';
import 'dart:convert';

import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/scheduler_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const firstSession = '11111111-1111-1111-1111-111111111111';
const secondSession = '22222222-2222-2222-2222-222222222222';

/// The bridge retains only associations which it has actually received.
/// Keeping a path in the controller's current draft is not persistence.
class RepositoryContinuityAdapter implements SchedulerAdapter {
  String savedRepository = r'C:\old\checkout';
  final roots = <String, String>{};
  final invalidRepositories = <String>{};
  Map<String, dynamic>? discoveryOverride;
  final saves = <Map<String, dynamic>>[];
  final selections = <Map<String, dynamic>>[];
  Completer<void>? releaseSelection;
  Completer<void>? firstSaveEntered;
  Completer<void>? releaseFirstSave;
  bool rejectSaves = false;
  int activeWrites = 0;
  int maximumWrites = 0;

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    switch (action) {
      case 'load':
        return {
          'sessions': [
            {'Id': firstSession, 'Display': 'First conversation'},
            {'Id': secondSession, 'Display': 'Second conversation'},
          ],
          'pending': [],
          'history': [],
          'settings': {
            'draft': {
              'sessionId': firstSession,
              'repo': savedRepository,
              'access': 'read-only',
              'model': 'test-model',
              'effort': 'medium',
              'message': 'Resume.',
            },
          },
        };
      case 'usage':
        return {
          'ok': true,
          'model': 'test-model',
          'accountId': 'workspace-sha256:${'a' * 64}',
          'models': [
            {
              'id': 'test-model',
              'efforts': ['medium'],
              'defaultEffort': 'medium',
            },
          ],
          'windows': [],
        };
      case 'select':
        selections.add(Map<String, dynamic>.of(payload));
        if (releaseSelection != null) await releaseSelection!.future;
        final requested = payload['repository'] as String?;
        final root =
            requested != null &&
                requested.isNotEmpty &&
                !invalidRepositories.contains(requested)
            ? requested
            : roots[payload['sessionId']];
        return {
          'sessionId': payload['sessionId'],
          'found': discoveryOverride ?? (root == null ? null : {'Root': root}),
        };
      case 'save':
        // Copy at the transport boundary, as JSON encoding does in production.
        final request = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(payload)) as Map,
        );
        activeWrites++;
        if (activeWrites > maximumWrites) maximumWrites = activeWrites;
        if (saves.isEmpty && firstSaveEntered != null) {
          firstSaveEntered!.complete();
          await releaseFirstSave!.future;
        }
        if (rejectSaves) {
          activeWrites--;
          throw SchedulerException('Test preferences write failed');
        }
        saves.add(request);
        final draft = request['draft'] as Map;
        final path = draft['repo'] as String;
        if (path.isNotEmpty) roots[draft['sessionId'] as String] = path;
        activeWrites--;
        return {'saved': true};
      default:
        return {};
    }
  }
}

void main() {
  test('incomplete discovery explains the limit without selecting partial evidence', () async {
    const reason = 'Repository evidence scan exceeded its time budget.';
    final adapter = RepositoryContinuityAdapter()
      ..savedRepository = ''
      ..discoveryOverride = {
        'Root': null,
        'Incomplete': true,
        'Source': reason,
        'Candidates': [r'C:\partial\checkout'],
        'AlternativeRoots': [r'C:\partial\checkout'],
      };
    final controller = SchedulerController(adapter);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.selectSession(firstSession);

    expect(controller.repo, isEmpty);
    expect(
      controller.repositoryWarning,
      'Repository lookup incomplete: $reason Use Browse.',
    );
    expect(controller.repositoryAlternatives, [r'C:\partial\checkout']);
  });

  test(
    'restored repository is verified without replacing a valid manual choice',
    () async {
      final adapter = RepositoryContinuityAdapter()
        ..roots[firstSession] = r'C:\automatic\different';
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.selectSession(firstSession);

      expect(adapter.selections, hasLength(1));
      expect(adapter.selections.single['repository'], r'C:\old\checkout');
      expect(controller.repo, r'C:\old\checkout');
    },
  );

  test(
    'missing restored checkout cannot suppress repository discovery forever',
    () async {
      final adapter = RepositoryContinuityAdapter()
        ..invalidRepositories.add(r'C:\old\checkout')
        ..roots[firstSession] = r'C:\actual\checkout';
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.selectSession(firstSession);

      expect(controller.repo, r'C:\actual\checkout');
    },
  );

  test(
    'manual edit wins over delayed verification of a restored repository',
    () async {
      final adapter = RepositoryContinuityAdapter()
        ..invalidRepositories.add(r'C:\old\checkout')
        ..roots[firstSession] = r'C:\automatic\checkout'
        ..releaseSelection = Completer<void>();
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();
      expect(adapter.selections, hasLength(1));
      controller.edit(repository: r'C:\manual\new');
      adapter.releaseSelection!.complete();
      await controller.selectSession(firstSession);
      await Future<void>.delayed(Duration.zero);

      expect(controller.repo, r'C:\manual\new');
    },
  );

  test(
    'switching before debounce persists the outgoing manual repository',
    () async {
      final adapter = RepositoryContinuityAdapter();
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();

      controller.edit(repository: r'C:\chosen\first');
      await controller.selectSession(secondSession);
      await controller.flushPreferences();

      expect(adapter.roots[firstSession], r'C:\chosen\first');
      expect(controller.repo, isEmpty);
      expect(adapter.roots.containsKey(secondSession), isFalse);
      await controller.selectSession(firstSession);
      expect(controller.repo, r'C:\chosen\first');
    },
  );

  test(
    'automatic discovery survives switching before its draft is saved',
    () async {
      final adapter = RepositoryContinuityAdapter()
        ..savedRepository = ''
        ..roots[firstSession] = r'C:\found\first';
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.selectSession(firstSession);
      expect(controller.repo, r'C:\found\first');

      // The transient discovery source disappears, as a cancelled task can.
      adapter.roots.remove(firstSession);
      await controller.selectSession(secondSession);
      await controller.flushPreferences();
      await controller.selectSession(firstSession);

      expect(controller.repo, r'C:\found\first');
    },
  );

  test(
    'queued saves preserve each session while coalescing its edits',
    () async {
      final adapter = RepositoryContinuityAdapter()
        ..firstSaveEntered = Completer<void>()
        ..releaseFirstSave = Completer<void>();
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();
      controller.edit(instruction: 'Start a slow save');
      final firstWrite = controller.save();
      await adapter.firstSaveEntered!.future;

      controller.edit(repository: r'C:\chosen\intermediate');
      final intermediateWrite = controller.save();
      controller.edit(repository: r'C:\chosen\first-final');
      final selection = controller.selectSession(secondSession);
      controller.edit(repository: r'C:\chosen\second');
      final secondWrite = controller.save();
      adapter.releaseFirstSave!.complete();
      await Future.wait([
        firstWrite,
        intermediateWrite,
        selection,
        secondWrite,
      ]);
      await controller.flushPreferences();

      expect(adapter.maximumWrites, 1);
      expect(adapter.roots[firstSession], r'C:\chosen\first-final');
      expect(adapter.roots[secondSession], r'C:\chosen\second');
      expect((adapter.saves.last['draft'] as Map)['sessionId'], secondSession);
      expect(controller.repo, r'C:\chosen\second');
    },
  );

  test(
    'a failed outgoing save is retained for retry after changing sessions',
    () async {
      final adapter = RepositoryContinuityAdapter()..rejectSaves = true;
      final controller = SchedulerController(adapter);
      addTearDown(controller.dispose);
      await controller.start();
      controller.edit(repository: r'C:\chosen\first');
      await controller.selectSession(secondSession);
      expect(await controller.flushPreferences(), isFalse);

      adapter.rejectSaves = false;
      expect(await controller.flushPreferences(), isTrue);
      expect(adapter.roots[firstSession], r'C:\chosen\first');
      expect((adapter.saves.last['draft'] as Map)['sessionId'], secondSession);
    },
  );
}

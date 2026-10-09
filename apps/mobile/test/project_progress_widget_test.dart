import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sababisha_pms_mobile/src/models/models.dart';
import 'package:sababisha_pms_mobile/src/screens/dashboard_screen.dart';
import 'package:sababisha_pms_mobile/src/services/api_client.dart';
import 'package:sababisha_pms_mobile/src/services/app_state.dart';
import 'package:sababisha_pms_mobile/src/services/session_store.dart';

void main() {
  testWidgets('project progress is identical for manager and contributor roles',
      (tester) async {
    for (final role in ['PROJECT_MANAGER', 'CONTRIBUTOR']) {
      final state = _dashboardState(projectRole: role);
      state.tasks = [
        _task('mine', ['user-1']),
        _task('theirs', ['user-2']),
      ];
      state.projectProgress = _progress();

      await _pumpDashboard(tester, state);
      final totalTasksCard =
          _metricCard(role == 'PROJECT_MANAGER' ? 'Total tasks' : 'My tasks');
      expect(
        find.descendant(
            of: totalTasksCard,
            matching: find.text(role == 'PROJECT_MANAGER' ? '10' : '1')),
        findsOneWidget,
      );
      if (role == 'PROJECT_MANAGER') {
        expect(
          find.descendant(of: _metricCard('Open'), matching: find.text('6')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: _metricCard('Overdue'), matching: find.text('2')),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: _metricCard('Completed'), matching: find.text('4')),
          findsOneWidget,
        );
      } else {
        expect(
          find.descendant(of: _metricCard('My open'), matching: find.text('1')),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: _metricCard('My overdue'), matching: find.text('0')),
          findsOneWidget,
        );
      }
      await _scrollToProjectHealth(tester);
      await tester.pumpAndSettle();

      expect(find.text('40%'), findsOneWidget);
      expect(find.text('4 of 10 tasks complete'), findsOneWidget);
      expect(find.text('Overdue 2'), findsOneWidget);
      expect(find.text('In Progress'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('empty project and non-empty zero percent are distinct',
      (tester) async {
    final emptyState = _dashboardState()
      ..projectProgress = _progress(
        hasTasks: false,
        total: 0,
        completed: 0,
        percent: null,
        outstanding: 0,
        overdue: 0,
      );
    await _pumpDashboard(tester, emptyState);
    await _scrollToProjectHealth(tester);
    await tester.pumpAndSettle();
    expect(find.text('No tasks'), findsOneWidget);
    expect(find.text('0%'), findsNothing);

    final zeroState = _dashboardState()
      ..projectProgress = _progress(
        hasTasks: true,
        total: 3,
        completed: 0,
        percent: 0,
        outstanding: 3,
        overdue: 1,
      );
    await _pumpDashboard(tester, zeroState);
    await _scrollToProjectHealth(tester);
    await tester.pumpAndSettle();
    expect(find.text('No tasks'), findsNothing);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('progress failure shows unavailable and retry recovers',
      (tester) async {
    final state = _dashboardState()
      ..projectProgressError = 'Endpoint unavailable.';
    await _pumpDashboard(tester, state);
    await _scrollToProjectHealth(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Project progress unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsOneWidget);
    expect(find.textContaining('Project progress unavailable'), findsNothing);
  });

  test('delayed prior-project response cannot replace the current project',
      () async {
    final oldResponse = Completer<http.Response>();
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/old-project/progress')) {
          return oldResponse.future;
        }
        if (request.url.path.endsWith('/new-project/progress')) {
          return http.Response(jsonEncode(_progressJson('new-project')), 200);
        }
        return _supportResponse(request);
      }),
    );
    final state = AppState(client);
    final oldProject = _project(id: 'old-project');
    final newProject = _project(id: 'new-project');

    final oldLoad = state.selectProject(oldProject);
    await Future<void>.delayed(Duration.zero);
    await state.selectProject(newProject);
    expect(state.projectProgress?.projectId, 'new-project');

    oldResponse
        .complete(http.Response(jsonEncode(_progressJson('old-project')), 200));
    await oldLoad;
    expect(state.projectProgress?.projectId, 'new-project');
    state.dispose();
  });

  test('sign out invalidates delayed project-progress responses', () async {
    final delayed = Completer<http.Response>();
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/progress')) return delayed.future;
        return _supportResponse(request);
      }),
    );
    final state = AppState(client);
    final loading = state.selectProject(_project(id: 'project-1'));
    await Future<void>.delayed(Duration.zero);
    state.signOut();
    delayed
        .complete(http.Response(jsonEncode(_progressJson('project-1')), 200));
    await loading;
    expect(state.projectProgress, isNull);
    expect(state.loadingProjectProgress, isFalse);
    state.dispose();
  });

  test('task status mutation refetches authoritative progress', () async {
    var progressRequests = 0;
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/progress')) {
          progressRequests++;
          final response = _progressJson('project-1')
            ..['completedTasks'] = progressRequests == 1 ? 4 : 5
            ..['progressPercent'] = progressRequests == 1 ? 40 : 50;
          return http.Response(jsonEncode(response), 200);
        }
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/tasks/task-1')) {
          expect(jsonDecode(request.body)['status'], 'DONE');
          return http.Response('', 204);
        }
        return _supportResponse(request);
      }),
    );
    final state = AppState(client)
      ..selectedProject = _project(id: 'project-1')
      ..tasks = [
        _task('task-1', ['user-1'])
      ];

    await state.refreshTasks();
    expect(state.projectProgress?.progressPercent, 40);
    await state.moveTask('task-1', 'DONE');

    expect(progressRequests, 2);
    expect(state.projectProgress?.progressPercent, 50);
    state.dispose();
  });
}

Future<void> _pumpDashboard(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: state,
    child: const MaterialApp(
      home: Scaffold(body: DashboardScreen()),
    ),
  ));
  await tester.pump();
}

Future<void> _scrollToProjectHealth(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Project health'),
    400,
    scrollable: find.byType(Scrollable).first,
  );
}

Finder _metricCard(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

AppState _dashboardState({String projectRole = 'PROJECT_MANAGER'}) {
  final api = ApiClient(
    sessionStore: _TestSessionStore(),
    httpClient: MockClient(_supportResponse),
  );
  final state = AppState(api)
    ..account = const Account(
      id: 'user-1',
      firstName: 'Test',
      lastName: 'Member',
      email: 'test@example.invalid',
    )
    ..selectedOrg = const Organization(
      id: 'org-1',
      name: 'Workspace',
      slug: 'workspace',
      role: 'MEMBER',
    )
    ..selectedProject = _project(id: 'project-1', role: projectRole)
    ..projects = [_project(id: 'project-1', role: projectRole)];
  return state;
}

Project _project({required String id, String role = 'PROJECT_MANAGER'}) =>
    Project(
      id: id,
      organizationId: 'org-1',
      name: 'Project $id',
      status: 'ACTIVE',
      role: role,
    );

Task _task(String id, List<String> assignees) => Task(
      id: id,
      projectId: 'project-1',
      title: 'Task $id',
      status: 'TO DO',
      priority: 'MEDIUM',
      assigneeIds: assignees,
    );

ProjectProgress _progress({
  bool hasTasks = true,
  int total = 10,
  int completed = 4,
  int? percent = 40,
  int outstanding = 6,
  int overdue = 2,
}) =>
    ProjectProgress(
      projectId: 'project-1',
      projectStatus: 'ACTIVE',
      hasTasks: hasTasks,
      totalEligibleTasks: total,
      completedTasks: completed,
      progressPercent: percent,
      outstandingTaskCount: outstanding,
      overdueTaskCount: overdue,
      timezoneIdUsed: 'Africa/Nairobi',
    );

Map<String, dynamic> _progressJson(String projectId) => {
      'projectId': projectId,
      'projectStatus': 'ACTIVE',
      'hasTasks': true,
      'totalEligibleTasks': 10,
      'completedTasks': 4,
      'progressPercent': 40,
      'outstandingTaskCount': 6,
      'overdueTaskCount': 2,
      'timezoneIdUsed': 'Africa/Nairobi',
    };

Future<http.Response> _supportResponse(http.Request request) async {
  if (request.url.path.endsWith('/tasks') ||
      request.url.path.endsWith('/members')) {
    return http.Response('[]', 200);
  }
  if (request.url.path.endsWith('/dashboard/metrics')) {
    return http.Response(
        jsonEncode({
          'myTasks': 0,
          'overdueTasks': 0,
          'completedTasks': 0,
          'inProgressTasks': 0,
          'totalTasks': 0,
        }),
        200);
  }
  if (request.url.path.endsWith('/progress')) {
    return http.Response(jsonEncode(_progressJson('project-1')), 200);
  }
  if (request.url.path.endsWith('/activity')) {
    return http.Response(jsonEncode({'items': [], 'nextCursor': null}), 200);
  }
  if (request.method == 'PATCH') return http.Response('', 204);
  return http.Response('{}', 200);
}

class _TestSessionStore extends SessionStore {
  _TestSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<AuthSession?> read() async => AuthSession(
        userId: 'user-1',
        accessToken: 'progress-token',
        refreshToken: 'refresh-token',
        accessTokenExpiresAt: DateTime.utc(2030),
      );
}

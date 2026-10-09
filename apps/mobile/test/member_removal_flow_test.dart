import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sababisha_pms_mobile/src/models/models.dart';
import 'package:sababisha_pms_mobile/src/screens/members_screen.dart';
import 'package:sababisha_pms_mobile/src/services/api_client.dart';
import 'package:sababisha_pms_mobile/src/services/app_state.dart';
import 'package:sababisha_pms_mobile/src/services/session_store.dart';

void main() {
  test('client rejects more than 100 resolutions before sending a request',
      () async {
    var requests = 0;
    final api = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 204);
      }),
    );
    final resolutions = List.generate(
      101,
      (index) => MemberTaskResolution(
        taskId: 'task-$index',
        action: 'UNASSIGN',
        replacementUserId: null,
      ),
    );
    await expectLater(
      api.confirmOrgMemberDeactivation(
        orgId: 'org-1',
        userId: 'member-1',
        snapshotHash: 'snapshot',
        resolutions: resolutions,
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'MEMBER_RESOLUTION_LIMIT_EXCEEDED',
      )),
    );
    expect(requests, 0);
  });

  test('client rejects request bodies larger than 64 KiB before sending',
      () async {
    var requests = 0;
    final api = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 204);
      }),
    );
    final resolutions = List.generate(
      100,
      (index) => MemberTaskResolution(
        taskId:
            '${index.toString().padLeft(3, '0')}-${List.filled(700, 'x').join()}',
        action: 'UNASSIGN',
        replacementUserId: null,
      ),
    );
    await expectLater(
      api.confirmOrgMemberDeactivation(
        orgId: 'org-1',
        userId: 'member-1',
        snapshotHash: 'snapshot',
        resolutions: resolutions,
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'MEMBER_RESOLUTION_LIMIT_EXCEEDED',
      )),
    );
    expect(requests, 0);
  });

  testWidgets(
      'project removal refreshes a stale preview and requires a new choice',
      (tester) async {
    final fixture = _Fixture();
    fixture.backend.staleFirstConfirmation = true;
    await _openMembers(tester, fixture);
    await tester.tap(find.text('Mobile Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();

    expect(fixture.backend.previewCalls, 1);
    expect(find.text('Review assignments for Taylor Member.'), findsOneWidget);
    expect(find.text('Implement client workflow'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('removal-action-task-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reassign').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('removal-replacement-task-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morgan Eligible').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();

    expect(fixture.backend.confirmBodies, hasLength(1));
    expect(fixture.backend.confirmBodies.first['snapshotHash'], 'snapshot-1');
    expect(fixture.backend.previewCalls, 2);
    expect(
        find.text(
            'The preview changed. Review this updated information and confirm again.'),
        findsOneWidget);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('removal-action-task-1')),
            )
            .initialValue,
        isNull);
    expect(fixture.backend.removed, isFalse);

    await tester.tap(find.byKey(const ValueKey('removal-action-task-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave unassigned').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();

    expect(fixture.backend.confirmBodies, hasLength(2));
    expect(fixture.backend.confirmBodies.last['snapshotHash'], 'snapshot-2');
    expect(fixture.backend.confirmBodies.last['resolutions'], [
      {
        'taskId': 'task-1',
        'action': 'UNASSIGN',
        'replacementUserId': null,
      }
    ]);
    expect(fixture.backend.directDeleteCalls, 0);
    expect(fixture.backend.removed, isTrue);
    await _closeMembers(tester, fixture);
  });

  testWidgets(
      'organization deactivation resolves tasks across projects in one request',
      (tester) async {
    final fixture = _Fixture()..backend.organizationPreview = true;
    await _openMembers(tester, fixture);
    await tester.tap(find.text('MEMBER').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();

    expect(find.text('Project project-1 · ACTIVE'), findsOneWidget);
    expect(find.text('Project project-2 · ACTIVE'), findsOneWidget);
    expect(find.text('Task in project one'), findsOneWidget);
    expect(find.text('Task in project two'), findsOneWidget);
    for (final taskId in ['task-1', 'task-2']) {
      await tester.tap(find.byKey(ValueKey('removal-action-$taskId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave unassigned').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Deactivate member'));
    await tester.pumpAndSettle();

    expect(fixture.backend.orgConfirmCalls, 1);
    expect(fixture.backend.orgConfirmBody?['snapshotHash'], 'org-snapshot');
    expect(fixture.backend.orgConfirmBody?['resolutions'], [
      {'taskId': 'task-1', 'action': 'UNASSIGN', 'replacementUserId': null},
      {'taskId': 'task-2', 'action': 'UNASSIGN', 'replacementUserId': null},
    ]);
    expect(fixture.backend.directDeleteCalls, 0);
    expect(fixture.backend.removed, isTrue);
    await _closeMembers(tester, fixture);
  });

  testWidgets(
      'preview permission failure keeps member visible and shows no success',
      (tester) async {
    final fixture = _Fixture()..backend.previewForbidden = true;
    await _openMembers(tester, fixture);
    await tester.tap(find.text('Mobile Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('You do not have permission to remove this member.'),
        findsOneWidget);
    expect(fixture.backend.removed, isFalse);
    expect(find.text('Taylor Member'), findsWidgets);
    await _closeMembers(tester, fixture);
  });

  testWidgets(
      'archived task requires lifecycle acknowledgement without replacement',
      (tester) async {
    final fixture = _Fixture()..backend.archivedPreview = true;
    await _openMembers(tester, fixture);
    await tester.tap(find.text('Mobile Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Acknowledge lifecycle inactivation; no replacement will be assigned.'),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('removal-replacement-task-1')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Remove member'))
            .onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Remove member'))
            .onPressed,
        isNotNull);
    expect(
        find.textContaining(
            'will be inactivated while preserving attribution.'),
        findsOneWidget);
    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();
    expect(fixture.backend.confirmBodies.single['resolutions'], [
      {
        'taskId': 'task-1',
        'action': 'ACCEPT_LIFECYCLE_INACTIVATION',
        'replacementUserId': null,
      }
    ]);
    await _closeMembers(tester, fixture);
  });
}

Future<void> _openMembers(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: fixture.state,
    child: const MaterialApp(home: Scaffold(body: MembersScreen())),
  ));
  await tester.pumpAndSettle();
}

Future<void> _closeMembers(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  fixture.state.dispose();
}

class _Fixture {
  _Fixture() {
    backend = _MockRemovalBackend();
    state = AppState(ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient(backend.handle),
    ))
      ..account = const Account(
        id: 'actor-1',
        firstName: 'Project',
        lastName: 'Admin',
        email: 'admin@example.invalid',
      )
      ..selectedOrg = const Organization(
        id: 'org-1',
        name: 'Example Organization',
        slug: 'example',
        role: 'OWNER',
      )
      ..selectedProject = const Project(
        id: 'project-1',
        organizationId: 'org-1',
        name: 'Mobile Project',
        status: 'ACTIVE',
        role: 'PROJECT_MANAGER',
      )
      ..orgMembers = [
        _member('actor-1', 'OWNER'),
        _member('member-1', 'MEMBER')
      ]
      ..projectMembers = [
        _member('actor-1', 'PROJECT_MANAGER'),
        _member('member-1', 'CONTRIBUTOR')
      ];
  }
  late final _MockRemovalBackend backend;
  late final AppState state;
}

Member _member(String id, String role) => Member(
      id: id,
      userId: id,
      firstName: id == 'member-1' ? 'Taylor' : 'Project',
      lastName: id == 'member-1' ? 'Member' : 'Admin',
      email: '$id@example.invalid',
      role: role,
    );

class _MockRemovalBackend {
  bool organizationPreview = false;
  bool previewForbidden = false;
  bool archivedPreview = false;
  bool staleFirstConfirmation = false;
  bool removed = false;
  int previewCalls = 0;
  int orgConfirmCalls = 0;
  int directDeleteCalls = 0;
  final List<Map<String, dynamic>> confirmBodies = [];
  Map<String, dynamic>? orgConfirmBody;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'GET' &&
        path == '/api/v1/projects/project-1/members/member-1/removal-preview') {
      previewCalls++;
      if (previewForbidden) {
        return _json(
            {'code': 'MEMBER_REMOVAL_FORBIDDEN', 'message': 'Forbidden'}, 403);
      }
      return _json(_preview(snapshot: 'snapshot-$previewCalls'));
    }
    if (request.method == 'POST' &&
        path == '/api/v1/projects/project-1/members/member-1/remove') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      confirmBodies.add(body);
      if (staleFirstConfirmation && confirmBodies.length == 1) {
        return _json(
            {'code': 'MEMBER_REMOVAL_PREVIEW_STALE', 'message': 'Stale'}, 409);
      }
      removed = true;
      return http.Response('', 204);
    }
    if (request.method == 'GET' &&
        path ==
            '/api/v1/organizations/org-1/members/member-1/deactivation-preview') {
      return _json(_preview(snapshot: 'org-snapshot', multiProject: true));
    }
    if (request.method == 'POST' &&
        path == '/api/v1/organizations/org-1/members/member-1/deactivate') {
      orgConfirmCalls++;
      orgConfirmBody = jsonDecode(request.body) as Map<String, dynamic>;
      removed = true;
      return http.Response('', 204);
    }
    if (request.method == 'DELETE' && path.contains('/members/')) {
      directDeleteCalls++;
      return http.Response('', 204);
    }
    if (path == '/api/v1/organizations/org-1/members') {
      return _json(removed
          ? [_memberJson('actor-1', 'OWNER')]
          : [
              _memberJson('actor-1', 'OWNER'),
              _memberJson('member-1', 'MEMBER'),
            ]);
    }
    if (path == '/api/v1/organizations/org-1/projects' ||
        path == '/api/v1/projects') {
      return _json([_projectJson('project-1')]);
    }
    if (path == '/api/v1/organizations/org-1/invitations') return _json([]);
    if (path == '/api/v1/projects/project-1/members') {
      return _json(removed
          ? [_memberJson('actor-1', 'PROJECT_MANAGER')]
          : [
              _memberJson('actor-1', 'PROJECT_MANAGER'),
              _memberJson('member-1', 'CONTRIBUTOR'),
            ]);
    }
    if (path == '/api/v1/tasks') return _json({'data': []});
    if (path == '/api/v1/dashboard/metrics') {
      return _json({
        'myTasks': 0,
        'overdueTasks': 0,
        'completedTasks': 0,
        'inProgressTasks': 0,
        'totalTasks': 0
      });
    }
    if (path == '/api/v1/projects/project-1/progress') {
      return _json({
        'projectId': 'project-1',
        'projectStatus': 'ACTIVE',
        'hasTasks': false,
        'totalEligibleTasks': 0,
        'completedTasks': 0,
        'progressPercent': null,
        'outstandingTaskCount': 0,
        'overdueTaskCount': 0,
        'timezoneIdUsed': 'UTC'
      });
    }
    return _json({'message': 'Unexpected test request: $path'}, 404);
  }

  Map<String, dynamic> _preview(
          {required String snapshot, bool multiProject = false}) =>
      {
        'projectId': multiProject ? null : 'project-1',
        'organizationId': 'org-1',
        'memberId': 'member-1',
        'snapshotHash': snapshot,
        'affectedTaskCount': multiProject ? 2 : 1,
        'affectedProjects': [
          if (archivedPreview)
            _archivedProject()
          else
            _affectedProject(
                'project-1',
                'task-1',
                multiProject
                    ? 'Task in project one'
                    : 'Implement client workflow'),
          if (multiProject)
            _affectedProject('project-2', 'task-2', 'Task in project two'),
        ],
        'expiredTrashCleanup': [],
      };

  Map<String, dynamic> _archivedProject() => {
        'projectId': 'project-1',
        'lifecycle': 'ARCHIVED',
        'ownerTransferRequired': false,
        'managerInvariantBlocked': false,
        'eligibleReplacementMembers': [],
        'tasks': [
          {
            'taskId': 'task-1',
            'parentTaskId': null,
            'title': 'Implement client workflow',
            'status': 'TO DO',
            'currentAssigneeIds': ['member-1'],
            'requiredResolution': 'ACCEPT_LIFECYCLE_INACTIVATION',
          }
        ],
        'historicalAttributionsToInactivate': [
          {
            'taskId': 'done-task',
            'status': 'DONE',
            'taskInTrash': false,
            'currentAssigneeIds': ['member-1'],
            'actionOnConfirm': 'UNASSIGNED',
          }
        ],
      };

  Map<String, dynamic> _affectedProject(
          String projectId, String taskId, String title) =>
      {
        'projectId': projectId,
        'lifecycle': 'ACTIVE',
        'ownerTransferRequired': false,
        'managerInvariantBlocked': false,
        'eligibleReplacementMembers': [
          {'userId': 'replacement-1', 'displayName': 'Morgan Eligible'}
        ],
        'tasks': [
          {
            'taskId': taskId,
            'parentTaskId': null,
            'title': title,
            'status': 'TO DO',
            'currentAssigneeIds': ['member-1'],
            'requiredResolution': 'REASSIGN_OR_UNASSIGN',
          }
        ],
        'historicalAttributionsToInactivate': [],
      };

  Map<String, dynamic> _memberJson(String id, String role) => {
        'id': id,
        'userId': id,
        'firstName': id == 'member-1' ? 'Taylor' : 'Project',
        'lastName': id == 'member-1' ? 'Member' : 'Admin',
        'email': '$id@example.invalid',
        'role': role,
      };

  Map<String, dynamic> _projectJson(String id) => {
        'id': id,
        'organizationId': 'org-1',
        'name': id == 'project-1' ? 'Mobile Project' : 'Other Project',
        'status': 'ACTIVE',
        'role': 'PROJECT_MANAGER',
      };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);
}

class _TestSessionStore extends SessionStore {
  _TestSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<AuthSession?> read() async => AuthSession(
        userId: 'actor-1',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        accessTokenExpiresAt: DateTime.utc(2030),
      );
}

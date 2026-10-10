import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sababisha_pms_mobile/src/models/models.dart';
import 'package:sababisha_pms_mobile/src/services/api_client.dart';
import 'package:sababisha_pms_mobile/src/services/session_store.dart';

void main() {
  test('uses the Android emulator API address by default', () {
    expect(apiBaseUrl, 'https://taskflow-api-rki8.onrender.com/api/v1');
  });

  test('API errors retain status and message', () {
    const error = ApiException('Forbidden', statusCode: 403);
    expect(error.statusCode, 403);
    expect(error.toString(), 'Forbidden');
  });

  test('API errors retain the stable server error code', () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'code': 'project_must_retain_manager',
              'message': 'Server message',
            }),
            400,
          )),
    );

    await expectLater(
      client.updateProjectMemberRole(
        projectId: 'project-1',
        userId: 'member-1',
        role: 'VIEWER',
      ),
      throwsA(
        isA<ApiException>()
            .having(
                (error) => error.code, 'code', 'project_must_retain_manager')
            .having((error) => error.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('suggestTask posts the project prompt and parses the typed draft',
      () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/ai/tasks/suggest');
        expect(request.headers, contains('Authorization'));
        expect(jsonDecode(request.body), {
          'projectId': 'project-1',
          'prompt': 'Plan the launch checklist',
        });
        return http.Response(
          jsonEncode({
            'title': 'Prepare launch checklist',
            'description': 'Coordinate launch readiness.',
            'priority': 'HIGH',
            'subtasks': ['Confirm owners', 'Review readiness'],
          }),
          200,
        );
      }),
    );

    final suggestion = await client.suggestTask(
      projectId: 'project-1',
      prompt: 'Plan the launch checklist',
    );

    expect(suggestion.title, 'Prepare launch checklist');
    expect(suggestion.priority, 'HIGH');
    expect(suggestion.subtasks, ['Confirm owners', 'Review readiness']);
  });

  test('updateTask sends explicit date-clear flags and accepts no content',
      () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/tasks/task-1');
        expect(jsonDecode(request.body), {
          'title': 'Updated task',
          'clearStartDate': true,
          'clearDueDate': true,
        });
        return http.Response('', 204);
      }),
    );

    await client.updateTask(
      taskId: 'task-1',
      title: 'Updated task',
      clearStartDate: true,
      clearDueDate: true,
    );
  });

  test('updateProjectMemberRole PATCHes the existing project member', () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/projects/project-1/members/member-1');
        expect(request.headers['Authorization'], 'Bearer access-token');
        expect(jsonDecode(request.body), {'role': 'TEAM_LEAD'});
        return http.Response('', 204);
      }),
    );

    await client.updateProjectMemberRole(
      projectId: 'project-1',
      userId: 'member-1',
      role: 'TEAM_LEAD',
    );
  });

  test(
      'adminActivityPage sends organization and project filters and parses scope',
      () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/admin/activity-events');
        expect(request.url.queryParameters['organizationId'], 'org-1');
        expect(request.url.queryParameters['projectId'], 'project-1');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'eventId': 'event-1',
                'organizationId': 'org-1',
                'organizationName': 'Workspace One',
                'projectId': 'project-1',
                'projectName': 'Project One',
                'actorUserId': 'user-1',
                'actorName': 'Activity Actor',
                'category': 'Tasks',
                'action': 'task.updated',
                'entityType': 'task',
                'entityId': 'task-1',
                'entityName': 'Task One',
                'description': 'Updated Task One',
                'status': 'succeeded',
                'correlationId': 'request-1',
                'createdAt': '2026-10-10T09:00:00Z',
              }
            ],
            'nextCursor': null,
          }),
          200,
        );
      }),
    );

    final page = await client.adminActivityPage(
      organizationId: 'org-1',
      projectId: 'project-1',
    );

    expect(page.items.single.projectId, 'project-1');
    expect(page.items.single.projectName, 'Project One');
  });

  test('adminProjects requests selected organization and retained Trash projects',
      () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/admin/projects');
        expect(request.url.queryParameters['organizationId'], 'org-1');
        expect(request.url.queryParameters['includeTrashed'], 'true');
        return http.Response(
          jsonEncode([
            {
              'id': 'project-trashed',
              'name': 'Retained project',
              'organizationName': 'Workspace One',
              'status': 'ACTIVE',
              'taskCount': 0,
              'createdAt': '2026-10-01T00:00:00Z',
              'deletedAt': '2026-10-09T00:00:00Z',
            }
          ]),
          200,
        );
      }),
    );

    final projects = await client.adminProjects(
      organizationId: 'org-1',
      includeTrashed: true,
    );

    expect(projects.single.id, 'project-trashed');
    expect(projects.single.isTrashed, isTrue);
  });
}

class _TestSessionStore extends SessionStore {
  _TestSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<AuthSession?> read() async => AuthSession(
        userId: 'user-1',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        accessTokenExpiresAt: DateTime.utc(2030),
      );
}

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

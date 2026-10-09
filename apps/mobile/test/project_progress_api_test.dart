import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sababisha_pms_mobile/src/models/models.dart';
import 'package:sababisha_pms_mobile/src/services/api_client.dart';
import 'package:sababisha_pms_mobile/src/services/session_store.dart';

void main() {
  test('projectProgress requests and parses the authoritative endpoint',
      () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/projects/project-1/progress');
        expect(request.headers['Authorization'], 'Bearer progress-token');
        return http.Response(jsonEncode(_response()), 200);
      }),
    );

    final progress = await client.projectProgress('project-1');

    expect(progress.projectId, 'project-1');
    expect(progress.projectStatus, 'ACTIVE');
    expect(progress.hasTasks, isTrue);
    expect(progress.totalEligibleTasks, 10);
    expect(progress.completedTasks, 4);
    expect(progress.progressPercent, 40);
    expect(progress.outstandingTaskCount, 6);
    expect(progress.overdueTaskCount, 2);
    expect(progress.timezoneIdUsed, 'Africa/Nairobi');
  });

  test('projectProgress preserves null percentage for an empty project',
      () async {
    final payload = _response()
      ..addAll({
        'hasTasks': false,
        'totalEligibleTasks': 0,
        'completedTasks': 0,
        'progressPercent': null,
        'outstandingTaskCount': 0,
        'overdueTaskCount': 0,
      });
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient:
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
    );

    final progress = await client.projectProgress('project-1');

    expect(progress.hasTasks, isFalse);
    expect(progress.progressPercent, isNull);
  });

  test('projectProgress propagates authorization and server errors', () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({'code': 'project_forbidden', 'message': 'Forbidden'}),
            403,
          )),
    );

    await expectLater(
      client.projectProgress('project-1'),
      throwsA(isA<ApiException>()
          .having((error) => error.statusCode, 'statusCode', 403)
          .having((error) => error.code, 'code', 'project_forbidden')),
    );
  });

  test('projectProgress reports network failure instead of returning zero',
      () async {
    final client = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((_) async => throw StateError('offline')),
    );

    await expectLater(
      client.projectProgress('project-1'),
      throwsA(isA<ApiException>().having(
        (error) => error.message,
        'message',
        'Cannot reach the API. Check your connection and server address.',
      )),
    );
  });

  test('status labels use approved values and a readable fallback', () {
    expect(projectStatusLabel('PLANNING'), 'Planned');
    expect(projectStatusLabel('ACTIVE'), 'In Progress');
    expect(projectStatusLabel('ON_HOLD'), 'On Hold');
    expect(projectStatusLabel('COMPLETED'), 'Completed');
    expect(projectStatusLabel('FUTURE_STATE'), 'Future State');
    expect(taskStatusLabel('TO DO'), 'To Do');
    expect(taskStatusLabel('IN PROGRESS'), 'In Progress');
    expect(taskStatusLabel('REVIEW'), 'In Review');
    expect(taskStatusLabel('DONE'), 'Done');
    expect(taskStatusLabel('WAITING_FOR_QA'), 'Waiting For Qa');
  });
}

Map<String, dynamic> _response() => {
      'projectId': 'project-1',
      'projectStatus': 'ACTIVE',
      'hasTasks': true,
      'totalEligibleTasks': 10,
      'completedTasks': 4,
      'progressPercent': 40,
      'outstandingTaskCount': 6,
      'overdueTaskCount': 2,
      'timezoneIdUsed': 'Africa/Nairobi',
    };

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

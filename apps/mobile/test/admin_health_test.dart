import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sababisha_pms_mobile/src/models/models.dart';
import 'package:sababisha_pms_mobile/src/services/api_client.dart';
import 'package:sababisha_pms_mobile/src/services/app_state.dart';
import 'package:sababisha_pms_mobile/src/services/session_store.dart';

void main() {
  test('health response preserves unknown and unmeasured statuses', () {
    final health = AdminHealthStatus.fromJson({
      'overallStatus': 'unknown',
      'checkedAt': '2026-10-10T09:00:00Z',
      'components': [
        {
          'id': 'email',
          'name': 'Email service',
          'status': 'configured',
          'signal': 'configuration',
          'summary': 'Configured, not probed.',
        },
        {
          'id': 'realtime',
          'name': 'SignalR',
          'status': 'not_instrumented',
          'signal': 'not_instrumented',
          'summary': 'Not measured.',
        },
      ],
    });

    expect(health.overallStatus, 'unknown');
    expect(health.components.map((component) => component.status),
        ['configured', 'not_instrumented']);
  });

  test('health load clears stale data on failure and explicit retry recovers',
      () async {
    var requestCount = 0;
    final api = ApiClient(
      sessionStore: _TestSessionStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/admin/system-health');
        expect(request.headers['Authorization'], 'Bearer test-access');
        requestCount++;
        if (requestCount == 1) {
          throw TimeoutException('simulated health request timeout');
        }
        if (requestCount == 2) {
          return http.Response('{"code":"TEMPORARILY_UNAVAILABLE"}', 503);
        }
        return http.Response(
          jsonEncode({
            'overallStatus': 'unknown',
            'checkedAt': '2026-10-10T09:00:00Z',
            'components': [
              {
                'id': 'database',
                'name': 'SQL Server',
                'status': 'healthy',
                'signal': 'connectivity',
                'summary': 'Connectivity passed.',
              },
            ],
          }),
          200,
        );
      }),
    );
    final state = AppState(api)
      ..adminHealth = AdminHealthStatus.fromJson({
        'overallStatus': 'healthy',
        'checkedAt': '2026-10-09T09:00:00Z',
        'components': const [],
      });

    final firstLoad = state.loadAdminHealth();
    expect(state.loadingAdminHealth, isTrue);
    await firstLoad;
    expect(state.loadingAdminHealth, isFalse);
    expect(state.adminHealth, isNull,
        reason: 'A failed refresh must not leave stale health displayed.');

    await state.loadAdminHealth();
    expect(state.loadingAdminHealth, isFalse);
    expect(state.adminHealth, isNull,
        reason: 'An HTTP failure must also keep stale health cleared.');

    await state.loadAdminHealth();
    expect(state.loadingAdminHealth, isFalse);
    expect(state.adminHealth?.overallStatus, 'unknown');
    expect(state.adminHealth?.components.single.status, 'healthy');
    expect(requestCount, 3);
  });
}

class _TestSessionStore extends SessionStore {
  _TestSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<AuthSession?> read() async => AuthSession(
        userId: 'test-user',
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
        accessTokenExpiresAt: DateTime.utc(2030),
      );
}

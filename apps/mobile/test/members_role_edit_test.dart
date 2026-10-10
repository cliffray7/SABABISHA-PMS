import 'dart:async';
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
  testWidgets(
      'only admins and project managers can edit roles; guests see Viewer',
      (tester) async {
    final admin = await _openMembers(tester, orgRole: 'ADMIN');
    expect(find.byKey(const ValueKey('project-role-member-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-role-guest-1')), findsNothing);
    expect(find.text('VIEWER'), findsOneWidget);
    await _closeMembers(tester, admin);

    final manager = await _openMembers(
      tester,
      orgRole: 'MEMBER',
      projectRole: 'PROJECT_MANAGER',
    );
    expect(find.byKey(const ValueKey('project-role-member-1')), findsOneWidget);
    await _closeMembers(tester, manager);

    final lead = await _openMembers(
      tester,
      orgRole: 'MEMBER',
      projectRole: 'TEAM_LEAD',
    );
    expect(find.byKey(const ValueKey('project-role-member-1')), findsNothing);
    expect(find.text('CONTRIBUTOR'), findsOneWidget);
    await _closeMembers(tester, lead);

    final member = await _openMembers(tester, orgRole: 'MEMBER');
    expect(find.byKey(const ValueKey('project-role-member-1')), findsNothing);
    await _closeMembers(tester, member);
  });

  testWidgets('role update disables the control and reloads the saved role',
      (tester) async {
    final fixture = await _openMembers(tester);
    final pending = Completer<http.Response>();
    fixture.backend.patchResponse = (_, __) => pending.future;

    await _chooseRole(tester, 'TEAM_LEAD');
    await tester.pump();
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('project-role-member-1')),
          )
          .onChanged,
      isNull,
    );

    pending.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(fixture.backend.memberRole, 'TEAM_LEAD');
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('project-role-member-1')),
          )
          .value,
      'TEAM_LEAD',
    );
    expect(find.byType(SnackBar), findsNothing);
    await _closeMembers(tester, fixture);
  });

  testWidgets('last-manager error is shown and the selected role rolls back',
      (tester) async {
    final fixture = await _openMembers(tester);
    fixture.backend.patchResponse = (_, __) async => http.Response(
          jsonEncode({
            'code': 'project_must_retain_manager',
            'message': 'Server message',
          }),
          400,
        );

    await _chooseRole(tester, 'VIEWER');
    await tester.pumpAndSettle();
    expect(
      find.text('This project must keep at least one active project manager.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('project-role-member-1')),
          )
          .value,
      'CONTRIBUTOR',
    );
    expect(fixture.backend.memberRole, 'CONTRIBUTOR');
    await _closeMembers(tester, fixture);
  });

  test('every documented role error code has a clear message', () {
    const messages = {
      'invalid_project_role': 'Choose one of the supported project roles.',
      'self_role_change_not_allowed':
          'You cannot change your own project role this way.',
      'guest_project_role_must_be_viewer':
          'Organization guests can only have the Viewer project role.',
      'project_must_retain_manager':
          'This project must keep at least one active project manager.',
      'project_role_update_forbidden':
          'You do not have permission to change project member roles.',
      'project_manager_grant_forbidden':
          'Only organization admins and project managers can grant the Project Manager role.',
      'project_role_update_conflict':
          'The project is busy. Refresh member data, then retry.',
    };

    for (final entry in messages.entries) {
      expect(
        projectRoleErrorMessage(
          ApiException('Server fallback', code: entry.key),
        ),
        entry.value,
      );
    }
    expect(
      projectRoleErrorMessage(const ApiException('Server fallback')),
      'Server fallback',
    );
  });
}

Future<_Fixture> _openMembers(
  WidgetTester tester, {
  String orgRole = 'OWNER',
  String projectRole = 'CONTRIBUTOR',
}) async {
  final fixture = _Fixture(orgRole: orgRole, projectRole: projectRole);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: fixture.state,
      child: const MaterialApp(
        home: Scaffold(body: MembersScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mobile Project'));
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _chooseRole(WidgetTester tester, String role) async {
  await tester.tap(find.byKey(const ValueKey('project-role-member-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(role).last);
  await tester.pump();
}

Future<void> _closeMembers(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  fixture.state.dispose();
}

class _Fixture {
  _Fixture({required String orgRole, required String projectRole}) {
    backend = _MockBackend();
    state = AppState(
      ApiClient(
        sessionStore: _TestSessionStore(),
        httpClient: MockClient(backend.handle),
      ),
    )
      ..account = const Account(
        id: 'actor-1',
        firstName: 'Project',
        lastName: 'Admin',
        email: 'admin@example.invalid',
      )
      ..selectedOrg = Organization(
        id: 'org-1',
        name: 'Example Organization',
        slug: 'example',
        role: orgRole,
      )
      ..selectedProject = Project(
        id: 'project-1',
        organizationId: 'org-1',
        name: 'Mobile Project',
        status: 'ACTIVE',
        role: projectRole,
      )
      ..orgMembers = [
        _member('member-1', role: 'MEMBER'),
        _member('guest-1', role: 'GUEST'),
      ]
      ..projectMembers = [
        _member('member-1', role: backend.memberRole),
        // Simulate a legacy elevated guest row; UI must still show Viewer.
        _member('guest-1', role: 'CONTRIBUTOR'),
      ];
  }

  late final _MockBackend backend;
  late final AppState state;
}

Member _member(String id, {required String role}) => Member(
      id: id,
      userId: id,
      firstName: id == 'guest-1' ? 'Guest' : 'Taylor',
      lastName: 'Member',
      email: '$id@example.invalid',
      role: role,
    );

class _MockBackend {
  String memberRole = 'CONTRIBUTOR';
  Future<http.Response> Function(http.Request, String)? patchResponse;

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'PATCH' &&
        request.url.path == '/api/v1/projects/project-1/members/member-1') {
      final role =
          (jsonDecode(request.body) as Map<String, dynamic>)['role'] as String;
      final response = patchResponse == null
          ? http.Response('', 204)
          : await patchResponse!(request, role);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        memberRole = role;
      }
      return response;
    }
    if (request.url.path == '/api/v1/projects/project-1/members') {
      return http.Response(
        jsonEncode([
          _memberJson('member-1', memberRole),
          _memberJson('guest-1', 'CONTRIBUTOR'),
        ]),
        200,
      );
    }
    if (request.url.path == '/api/v1/tasks') {
      return http.Response(jsonEncode({'data': []}), 200);
    }
    if (request.url.path == '/api/v1/dashboard/metrics') {
      return http.Response(jsonEncode({}), 200);
    }
    return http.Response(
      jsonEncode({'message': 'Unexpected test request: ${request.url.path}'}),
      404,
    );
  }

  Map<String, dynamic> _memberJson(String id, String role) => {
        'id': id,
        'userId': id,
        'firstName': id == 'guest-1' ? 'Guest' : 'Taylor',
        'lastName': 'Member',
        'email': '$id@example.invalid',
        'role': role,
      };
}

class _TestSessionStore extends SessionStore {
  _TestSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<AuthSession?> read() async => AuthSession(
        userId: 'actor-1',
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
        accessTokenExpiresAt: DateTime.utc(2030),
      );
}

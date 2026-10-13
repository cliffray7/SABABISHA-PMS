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
      'reactivation uses scoped preview, clears choices on stale snapshot, and confirms explicitly',
      (tester) async {
    final backend = _ReactivationBackend();
    final state = _createState(backend);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: MembersScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deactivated'));
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    await tester.tap(find.text('Reactivate').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Historical task assignments'), findsOneWidget);
    expect(find.text('Maximum role available to you: ADMIN.'), findsOneWidget);
    expect(find.text('Restricted Project'), findsOneWidget);
    expect(
        find.text(
            'You lack active project-management authority to restore access.'),
        findsOneWidget);

    final projectCheckbox = find.byType(Checkbox).first;
    expect(tester.widget<Checkbox>(projectCheckbox).value, isFalse,
        reason: 'Project access must default to none selected.');
    await tester.tap(projectCheckbox);
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));
    await tester.enterText(textFields.last, 'Returning to the team');
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Confirm reactivation');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(backend.confirmCount, 1);
    expect(backend.previewCount, 2,
        reason: 'A stale response must fetch a fresh member-specific preview.');
    expect(tester.widget<Checkbox>(projectCheckbox).value, isFalse,
        reason: 'A refreshed preview must clear project choices.');
    expect(find.textContaining('Permissions or project state changed'),
        findsOneWidget);
    expect(find.text('Maximum role available to you: MEMBER.'), findsOneWidget);
    final refreshedRoleField = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(refreshedRoleField.initialValue, 'MEMBER');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('ADMIN'), findsNothing,
        reason: 'The refreshed MEMBER limit must remove ADMIN from choices.');
    await tester.tap(find.text('MEMBER').last);
    await tester.pumpAndSettle();

    final secondConfirm =
        find.widgetWithText(FilledButton, 'Confirm reactivation');
    await tester.tap(secondConfirm);
    await tester.pumpAndSettle();
    expect(backend.confirmCount, 2,
        reason:
            'The refreshed preview must require an explicit second confirm.');
    expect(backend.lastRequest, {
      'role': 'MEMBER',
      'projectIds': <String>[],
      'snapshotHash': 'reactivation-snapshot-2',
      'reason': 'Returning to the team',
    });
    expect(find.text('No deactivated members.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}

AppState _createState(_ReactivationBackend backend) => AppState(
      ApiClient(
        sessionStore: _TestSessionStore(),
        httpClient: MockClient(backend.handle),
      ),
    )
      ..account = const Account(
        id: 'admin-1',
        firstName: 'Org',
        lastName: 'Admin',
        email: 'admin@example.invalid',
      )
      ..selectedOrg = Organization(
        id: 'org-1',
        name: 'Example Organization',
        slug: 'example',
        role: 'ADMIN',
      );

class _ReactivationBackend {
  int previewCount = 0;
  int confirmCount = 0;
  bool reactivated = false;
  Map<String, dynamic>? lastRequest;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'GET' &&
        path == '/api/v1/organizations/org-1/members/deactivated') {
      return _json(
          200,
          reactivated
              ? []
              : [
                  {
                    'userId': 'member-1',
                    'firstName': 'Taylor',
                    'lastName': 'Member',
                    'email': 'taylor@example.invalid',
                    'previousRole': 'MEMBER',
                    'joinedAtUtc': '2025-01-02T00:00:00Z',
                  }
                ]);
    }
    if (request.method == 'GET' &&
        path ==
            '/api/v1/organizations/org-1/members/member-1/reactivation-preview') {
      previewCount++;
      return _json(200, {
        'organizationId': 'org-1',
        'userId': 'member-1',
        'firstName': 'Taylor',
        'lastName': 'Member',
        'email': 'taylor@example.invalid',
        'previousOrganizationRole': 'MEMBER',
        'allowedMaxRole': previewCount == 1 ? 'ADMIN' : 'MEMBER',
        'snapshotHash': 'reactivation-snapshot-$previewCount',
        'eligibleProjects': [
          {
            'projectId': 'project-1',
            'name': 'Eligible Project',
            'lifecycle': 'ACTIVE',
            'previousProjectRole': 'PROJECT_MANAGER',
            'actorCanRestoreProject': true,
          },
          {
            'projectId': 'project-2',
            'name': 'Restricted Project',
            'lifecycle': 'ACTIVE',
            'previousProjectRole': 'TEAM_LEAD',
            'actorCanRestoreProject': false,
          },
        ],
      });
    }
    if (request.method == 'POST' &&
        path == '/api/v1/organizations/org-1/members/member-1/reactivate') {
      confirmCount++;
      lastRequest = jsonDecode(request.body) as Map<String, dynamic>;
      if (confirmCount == 1) {
        return _json(409, {
          'code': 'MEMBER_REACTIVATION_SNAPSHOT_STALE',
          'message': 'Preview stale.',
        });
      }
      reactivated = true;
      return http.Response('', 204);
    }
    if (request.method == 'GET' && path == '/api/v1/projects') {
      return _json(200, []);
    }
    if (request.method == 'GET' &&
        path == '/api/v1/organizations/org-1/members') {
      return _json(200, []);
    }
    if (request.method == 'GET' &&
        path == '/api/v1/organizations/org-1/invitations') {
      return _json(200, []);
    }
    return _json(
        404, {'message': 'Unexpected request: ${request.method} $path'});
  }

  http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

class _TestSessionStore extends SessionStore {
  _TestSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<AuthSession?> read() async => AuthSession(
        userId: 'admin-1',
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
        accessTokenExpiresAt: DateTime.utc(2030),
      );
}

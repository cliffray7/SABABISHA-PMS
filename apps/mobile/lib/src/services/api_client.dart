import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'session_store.dart';

/// API root.  Override with --dart-define=API_BASE_URL=... to point elsewhere.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://taskflow-api-rki8.onrender.com/api/v1',
);

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required SessionStore sessionStore, http.Client? httpClient})
      : _sessionStore = sessionStore,
        _http = httpClient ?? http.Client();

  final SessionStore _sessionStore;
  final http.Client _http;

  Uri _uri(String path, [Map<String, String>? params]) {
    final uri = Uri.parse('$apiBaseUrl$path');
    return params != null ? uri.replace(queryParameters: params) : uri;
  }

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<LoginChallenge> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final response = await _send('POST', '/auth/register', body: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'password': password,
    });
    return LoginChallenge.fromJson(_json(response));
  }

  Future<LoginChallenge> login({
    required String email,
    required String password,
  }) async {
    final response = await _send('POST', '/auth/login',
        body: {'email': email, 'password': password});
    return LoginChallenge.fromJson(_json(response));
  }

  Future<AuthSession> verifyOtp({
    required String email,
    required String code,
  }) async {
    final response = await _send('POST', '/auth/verify-otp',
        body: {'email': email, 'code': code});
    final session = AuthSession.fromJson(_json(response));
    await _sessionStore.save(session);
    return session;
  }

  Future<void> forgotPassword(String email) async {
    await _send('POST', '/auth/forgot-password', body: {'email': email});
  }

  Future<Account> account() async {
    final response = await _authorized('GET', '/account');
    return Account.fromJson(_json(response));
  }

  Future<Account> updateAccount({
    required String firstName,
    required String lastName,
    required String timezone,
  }) async {
    final response = await _authorized('PATCH', '/account', body: {
      'firstName': firstName,
      'lastName': lastName,
      'timezone': timezone,
    });
    return Account.fromJson(_json(response));
  }

  Future<void> logout() async {
    final session = await _sessionStore.read();
    if (session != null) {
      try {
        await _authorized('POST', '/auth/logout',
            body: {'refreshToken': session.refreshToken});
      } on ApiException {
        // Local credential removal is still the correct outcome.
      }
    }
    await _sessionStore.clear();
  }

  // ─── Organizations ────────────────────────────────────────────────────────

  Future<List<Organization>> organizations() async {
    final response = await _authorized('GET', '/organizations');
    final list = _jsonList(response);
    return list.map(Organization.fromJson).toList();
  }

  Future<Organization> createOrganization({required String name}) async {
    final response = await _authorized('POST', '/organizations',
        body: {'name': name});
    return Organization.fromJson(_json(response));
  }

  Future<List<Member>> orgMembers(String orgId) async {
    final response =
        await _authorized('GET', '/organizations/$orgId/members');
    return _jsonList(response).map(Member.fromJson).toList();
  }

  Future<void> updateMemberRole({
    required String orgId,
    required String userId,
    required String role,
  }) async {
    await _authorized('PATCH', '/organizations/$orgId/members/$userId',
        body: {'role': role});
  }

  Future<void> removeOrgMember({
    required String orgId,
    required String userId,
  }) async {
    await _authorized('DELETE', '/organizations/$orgId/members/$userId');
  }

  Future<List<Invitation>> orgInvitations(String orgId) async {
    final response =
        await _authorized('GET', '/organizations/$orgId/invitations');
    return _jsonList(response).map(Invitation.fromJson).toList();
  }

  Future<void> inviteMember({
    required String orgId,
    required String email,
    required String role,
  }) async {
    await _authorized('POST', '/organizations/$orgId/invitations',
        body: {'email': email, 'role': role});
  }

  Future<void> cancelInvitation({
    required String orgId,
    required String invitationId,
  }) async {
    await _authorized(
        'DELETE', '/organizations/$orgId/invitations/$invitationId');
  }

  Future<Organization> acceptInvitation(String token) async {
    final response = await _authorized(
        'POST', '/organizations/invitations/accept', body: {'token': token});
    return Organization.fromJson(_json(response));
  }

  // ─── Projects ────────────────────────────────────────────────────────────

  Future<List<Project>> projects(String orgId) async {
    final response = await _authorized('GET', '/projects',
        params: {'organizationId': orgId});
    return _jsonList(response).map(Project.fromJson).toList();
  }

  Future<Project> createProject({
    required String orgId,
    required String name,
    String? description,
    String? startDate,
    String? dueDate,
    String status = 'ACTIVE',
  }) async {
    final response = await _authorized('POST', '/projects', body: {
      'organizationId': orgId,
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
      'status': status,
    });
    return Project.fromJson(_json(response));
  }

  Future<Project> updateProject({
    required String projectId,
    String? name,
    String? description,
    String? startDate,
    String? dueDate,
    String? status,
  }) async {
    final response = await _authorized('PATCH', '/projects/$projectId', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
      if (status != null) 'status': status,
    });
    return Project.fromJson(_json(response));
  }

  Future<void> archiveProject(String projectId) async {
    await _authorized('DELETE', '/projects/$projectId');
  }

  Future<List<Member>> projectMembers(String projectId) async {
    final response =
        await _authorized('GET', '/projects/$projectId/members');
    return _jsonList(response).map(Member.fromJson).toList();
  }

  Future<void> addProjectMember({
    required String projectId,
    required String userId,
    required String role,
  }) async {
    await _authorized('POST', '/projects/$projectId/members',
        body: {'userId': userId, 'role': role});
  }

  Future<void> removeProjectMember({
    required String projectId,
    required String userId,
  }) async {
    await _authorized('DELETE', '/projects/$projectId/members/$userId');
  }

  // ─── Tasks ───────────────────────────────────────────────────────────────

  Future<List<Task>> tasks(String projectId) async {
    final response =
        await _authorized('GET', '/tasks', params: {'projectId': projectId});
    final body = _json(response);
    final list = body['data'] as List<dynamic>? ?? body['items'] as List<dynamic>? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();
  }

  Future<Task> createTask({
    required String projectId,
    required String title,
    String? description,
    String status = 'TO DO',
    String priority = 'MEDIUM',
    String? startDate,
    String? dueDate,
    List<String> assigneeIds = const [],
  }) async {
    final response =
        await _authorized('POST', '/projects/$projectId/tasks', body: {
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'status': status,
      'priority': priority,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
      'assigneeIds': assigneeIds,
    });
    return Task.fromJson(_json(response));
  }

  Future<Task> updateTask({
    required String taskId,
    String? title,
    String? description,
    String? status,
    String? priority,
    String? startDate,
    String? dueDate,
    List<String>? assigneeIds,
  }) async {
    final response = await _authorized('PATCH', '/tasks/$taskId', body: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
      if (assigneeIds != null) 'assigneeIds': assigneeIds,
    });
    return Task.fromJson(_json(response));
  }

  Future<void> deleteTask(String taskId) async {
    await _authorized('DELETE', '/tasks/$taskId');
  }

  // ─── Subtasks ────────────────────────────────────────────────────────────

  Future<List<Subtask>> subtasks(String taskId) async {
    final response = await _authorized('GET', '/tasks/$taskId/subtasks');
    return _jsonList(response).map(Subtask.fromJson).toList();
  }

  Future<Subtask> createSubtask({
    required String taskId,
    required String title,
  }) async {
    final response = await _authorized('POST', '/tasks/$taskId/subtasks',
        body: {'title': title});
    return Subtask.fromJson(_json(response));
  }

  Future<void> updateSubtask({
    required String taskId,
    required String subtaskId,
    required bool done,
  }) async {
    await _authorized('PATCH', '/tasks/$taskId/subtasks/$subtaskId',
        body: {'done': done});
  }

  Future<void> deleteSubtask({
    required String taskId,
    required String subtaskId,
  }) async {
    await _authorized('DELETE', '/tasks/$taskId/subtasks/$subtaskId');
  }

  // ─── Comments ────────────────────────────────────────────────────────────

  Future<List<Comment>> comments(String taskId) async {
    final response = await _authorized('GET', '/tasks/$taskId/comments');
    return _jsonList(response).map(Comment.fromJson).toList();
  }

  Future<Comment> addComment({
    required String taskId,
    required String content,
    String? parentCommentId,
    List<String> mentionedUserIds = const [],
  }) async {
    final response = await _authorized('POST', '/tasks/$taskId/comments',
        body: {
          'content': content,
          'mentionedUserIds': mentionedUserIds,
          if (parentCommentId != null) 'parentCommentId': parentCommentId,
        });
    return Comment.fromJson(_json(response));
  }

  // ─── Attachments ─────────────────────────────────────────────────────────

  Future<List<Attachment>> attachments(String taskId) async {
    final response = await _authorized('GET', '/tasks/$taskId/attachments');
    return _jsonList(response).map(Attachment.fromJson).toList();
  }

  Future<Attachment> uploadAttachment({
    required String taskId,
    required File file,
    required String fileName,
  }) async {
    final session = await _sessionStore.read();
    if (session == null) throw const ApiException('Session expired.', statusCode: 401);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl/tasks/$taskId/attachments'),
    );
    request.headers['Authorization'] = 'Bearer ${session.accessToken}';
    request.files.add(await http.MultipartFile.fromPath('file', file.path,
        filename: fileName));

    try {
      final streamed = await _http.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      return Attachment.fromJson(_json(_ensureSuccess(response)));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Upload failed. Check your connection.');
    }
  }

  Future<String> attachmentDownloadUrl(String attachmentId) {
    // Returns the authenticated download endpoint URL.
    return Future.value('$apiBaseUrl/attachments/$attachmentId/download');
  }

  // ─── Notifications ───────────────────────────────────────────────────────

  Future<List<Notice>> notifications() async {
    final response = await _authorized('GET', '/notifications');
    return _jsonList(response).map(Notice.fromJson).toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _authorized(
        'PATCH', '/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _authorized('PATCH', '/notifications/read-all');
  }

  // ─── Dashboard ───────────────────────────────────────────────────────────

  Future<DashboardMetrics> dashboardMetrics(String projectId) async {
    final response = await _authorized('GET', '/dashboard/metrics',
        params: {'projectId': projectId});
    return DashboardMetrics.fromJson(_json(response));
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  Future<http.Response> _authorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? params,
  }) async {
    var session = await _sessionStore.read();
    if (session == null) {
      throw const ApiException('Your session has expired.', statusCode: 401);
    }
    var response = await _send(method, path,
        body: body,
        params: params,
        accessToken: session.accessToken,
        allowUnauthorized: true);
    if (response.statusCode != 401) return _ensureSuccess(response);

    session = await _refresh(session.refreshToken);
    response = await _send(method, path,
        body: body,
        params: params,
        accessToken: session.accessToken,
        allowUnauthorized: true);
    return _ensureSuccess(response);
  }

  Future<AuthSession> _refresh(String refreshToken) async {
    try {
      final response = await _send('POST', '/auth/refresh',
          body: {'refreshToken': refreshToken});
      final session = AuthSession.fromJson(_json(response));
      await _sessionStore.save(session);
      return session;
    } on ApiException {
      await _sessionStore.clear();
      rethrow;
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? params,
    String? accessToken,
    bool allowUnauthorized = false,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    final uri = _uri(path, params);
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed =
          await _http.send(request).timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      return allowUnauthorized ? response : _ensureSuccess(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
          'Cannot reach the API. Check your connection and server address.');
    }
  }

  http.Response _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return response;
    final payload = _tryJson(response.body);
    final message = payload?['message'] ??
        (payload?['error'] as Map<String, dynamic>?)?['message'];
    throw ApiException(
      message is String
          ? message
          : 'The request could not be completed (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic> _json(http.Response response) =>
      _tryJson(response.body) ??
      (throw const ApiException('The server returned an invalid response.'));

  List<Map<String, dynamic>> _jsonList(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'] ?? decoded['items'] ?? decoded['value'];
        if (data is List) return data.cast<Map<String, dynamic>>();
      }
      return [];
    } on FormatException {
      return [];
    }
  }

  Map<String, dynamic>? _tryJson(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/api_response.dart';
import 'package:start_on/services/api_client.dart';
import 'package:start_on/services/notion_sync_service.dart';

void main() {
  test('status JSON parsing succeeds with snake_case fields', () {
    final result = NotionConnectionStatusParser.fromJson({
      'connected': true,
      'connection_id': 'connection-1',
      'database_id': 'database-1',
      'data_source_id': 'data-source-1',
      'database_title': 'Tasks',
      'database_url': 'https://www.notion.so/tasks',
      'last_synced_at': '2026-05-18T01:02:03+00:00',
      'last_successful_synced_at': '2026-05-18T01:03:03+00:00',
      'sync_status': 'success',
      'last_error_message': 'Safe public message',
    });

    expect(result.connected, isTrue);
    expect(result.connectionId, 'connection-1');
    expect(result.databaseId, 'database-1');
    expect(result.dataSourceId, 'data-source-1');
    expect(result.databaseTitle, 'Tasks');
    expect(result.databaseUrl, 'https://www.notion.so/tasks');
    expect(result.lastSyncedAt, '2026-05-18T01:02:03+00:00');
    expect(result.lastSuccessfulSyncedAt, '2026-05-18T01:03:03+00:00');
    expect(result.syncStatus, 'success');
    expect(result.lastErrorMessage, 'Safe public message');
  });

  test('nullable status fields parse safely', () {
    final result = NotionConnectionStatusParser.fromJson({
      'connected': false,
      'connection_id': null,
      'database_id': null,
      'data_source_id': null,
      'database_title': null,
      'database_url': null,
      'last_synced_at': null,
      'last_successful_synced_at': null,
      'sync_status': null,
      'last_error_message': null,
    });

    expect(result.connected, isFalse);
    expect(result.connectionId, isNull);
    expect(result.databaseId, isNull);
    expect(result.dataSourceId, isNull);
    expect(result.databaseTitle, isNull);
    expect(result.databaseUrl, isNull);
    expect(result.lastSyncedAt, isNull);
    expect(result.lastSuccessfulSyncedAt, isNull);
    expect(result.syncStatus, isNull);
    expect(result.lastErrorMessage, isNull);
  });

  test('invalid datetime strings return null getters', () {
    final result = NotionConnectionStatusParser.fromJson({
      'connected': true,
      'last_synced_at': 'not-a-date',
      'last_successful_synced_at': '   ',
    });

    expect(result.lastSyncedAt, 'not-a-date');
    expect(result.lastSyncedAtDateTime, isNull);
    expect(result.lastSuccessfulSyncedAt, isNull);
    expect(result.lastSuccessfulSyncedAtDateTime, isNull);
  });

  test('connect, sync, and disconnect call the backend API paths', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'connection_id': 'connection-1',
        'database_id': 'database-1',
        'database_title': 'Tasks',
        'sync_status': 'active',
      }),
      _successData({
        'database_id': 'database-1',
        'database_title': 'Tasks',
        'quests': [
          {
            'title': 'Study sockets',
            'difficulty': 'normal',
            'category': 'study',
            'exp': 50,
            'defaultDurationSeconds': 2700,
            'external_id': 'page-1',
          },
        ],
      }),
      _successData(const <String, dynamic>{}),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    await service.syncDatabase(
      const NotionSyncConfig(
        apiToken: 'notion-secret',
        databaseInput: '35bdd41fce07815292aedabdfc826f3b',
      ),
    );
    await service.disconnectConnection();

    expect(apiClient.requests[0].path, '/integrations/notion/connect');
    expect(apiClient.requests[1].path, '/integrations/notion/sync');
    expect(apiClient.requests[2].path, '/integrations/notion/connection');
    expect(apiClient.requests[0].body, {
      'notion_api_token': 'notion-secret',
      'data_source_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
    });
  });

  test('connect error handling returns user-safe message', () async {
    final apiClient = _FakeNotionApiClient(
      const [],
      postErrors: [
        ApiClientException(
          statusCode: 403,
          code: 'forbidden',
          message:
              'The selected Notion database or data source is unavailable, or the integration does not have access to it. Share the database with the integration and try again.',
        ),
      ],
    );
    final service = NotionSyncService(apiClient: apiClient);

    await expectLater(
      () => service.syncDatabase(
        const NotionSyncConfig(
          apiToken: 'notion-secret',
          databaseInput: '35bdd41fce07815292aedabdfc826f3b',
        ),
      ),
      throwsA(
        isA<NotionSyncException>().having(
          (error) => error.message,
          'message',
          'The selected Notion database or data source is unavailable, or the integration does not have access to it. Share the database with the integration and try again.',
        ),
      ),
    );
  });

  test('sync error handling returns user-safe message', () async {
    final apiClient = _FakeNotionApiClient(
      const [],
      postErrors: [
        ApiClientException(
          statusCode: 409,
          code: 'conflict',
          message:
              'The Notion connection was disconnected. Reconnect before syncing again.',
        ),
      ],
    );
    final service = NotionSyncService(apiClient: apiClient);

    await expectLater(
      () => service.syncSavedConnection(),
      throwsA(
        isA<NotionSyncException>().having(
          (error) => error.message,
          'message',
          'The Notion connection was disconnected. Reconnect before syncing again.',
        ),
      ),
    );
  });

  test('disconnect error handling returns user-safe message', () async {
    final apiClient = _FakeNotionApiClient(
      const [],
      deleteErrors: [
        ApiClientException(
          statusCode: 500,
          code: 'server_error',
          message: 'Failed to disconnect Notion.',
        ),
      ],
    );
    final service = NotionSyncService(apiClient: apiClient);

    await expectLater(
      () => service.disconnectConnection(),
      throwsA(
        isA<NotionSyncException>().having(
          (error) => error.message,
          'message',
          'Failed to disconnect Notion.',
        ),
      ),
    );
  });
}

Map<String, dynamic> _successData(Map<String, dynamic> data) {
  return {'success': true, 'data': data, 'error': null};
}

class _FakeNotionApiClient extends ApiClient {
  _FakeNotionApiClient(
    this.responses, {
    this.postErrors = const [],
    this.getErrors = const [],
    this.deleteErrors = const [],
  }) : super(baseUrl: 'http://localhost');

  final List<Object?> responses;
  final List<ApiClientException> postErrors;
  final List<ApiClientException> getErrors;
  final List<ApiClientException> deleteErrors;
  final List<_CapturedRequest> requests = [];

  @override
  Future<ApiResponse<T>> postResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(path: path, body: body));
    if (postErrors.isNotEmpty) {
      throw postErrors.removeAt(0);
    }
    return ApiResponse<T>.fromJson(responses.removeAt(0), parseData);
  }

  @override
  Future<ApiResponse<T>> getResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(path: path));
    if (getErrors.isNotEmpty) {
      throw getErrors.removeAt(0);
    }
    return ApiResponse<T>.fromJson(responses.removeAt(0), parseData);
  }

  @override
  Future<ApiResponse<T>> deleteResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(path: path, body: body));
    if (deleteErrors.isNotEmpty) {
      throw deleteErrors.removeAt(0);
    }
    return ApiResponse<T>.fromJson(responses.removeAt(0), parseData);
  }
}

class _CapturedRequest {
  const _CapturedRequest({required this.path, this.body});

  final String path;
  final Object? body;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/settings_screen.dart';
import 'package:start_on/services/api_client.dart';
import 'package:start_on/services/notion_sync_service.dart';
import 'package:start_on/storage/app_settings_store.dart';
import 'package:start_on/storage/local_data_store.dart';

void main() {
  test('syncDatabase connects then syncs through backend endpoints', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'connection_id': 'connection-1',
        'database_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
        'database_title': 'Tasks',
        'sync_status': 'active',
      }),
      _successData({
        'database_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
        'database_title': 'Tasks',
        'quests': [
          {
            'title': 'Study sockets',
            'difficulty': 'normal',
            'category': 'study',
            'exp': 50,
            'defaultDurationSeconds': 2700,
          },
        ],
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    final result = await service.syncDatabase(
      const NotionSyncConfig(
        apiToken: ' notion-secret ',
        databaseInput:
            'https://www.notion.so/Tasks-35bdd41fce07815292aedabdfc826f3b',
      ),
    );

    expect(apiClient.requests[0].path, '/integrations/notion/connect');
    expect(apiClient.requests[0].body, {
      'notion_api_token': 'notion-secret',
      'database_url':
          'https://www.notion.so/Tasks-35bdd41fce07815292aedabdfc826f3b',
    });
    expect(apiClient.requests[1].path, '/integrations/notion/sync');
    expect(apiClient.requests[1].body, const <String, dynamic>{});
    expect(result.databaseTitle, 'Tasks');
    expect(result.quests.single.title, 'Study sockets');
    expect(result.quests.single.difficulty, '보통');
    expect(result.quests.single.category, 'study');
    expect(result.quests.single.id, startsWith('notion:'));
  });

  test('syncDatabase sends UUID input as data source id', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'connection_id': 'connection-1',
        'database_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
        'database_title': 'Tasks',
        'sync_status': 'active',
      }),
      _successData({
        'database_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
        'database_title': 'Tasks',
        'quests': const [],
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    await service.syncDatabase(
      const NotionSyncConfig(
        apiToken: 'notion-secret',
        databaseInput: '35bdd41fce07815292aedabdfc826f3b',
      ),
    );

    expect(apiClient.requests.first.body, {
      'notion_api_token': 'notion-secret',
      'data_source_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
    });
  });

  test('syncSavedConnection uses saved server connection', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'database_id': '35bdd41f-ce07-8152-92ae-dabdfc826f3b',
        'database_title': 'Tasks',
        'quests': const [],
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    final result = await service.syncSavedConnection();

    expect(apiClient.requests.single.path, '/integrations/notion/sync');
    expect(apiClient.requests.single.body, const <String, dynamic>{});
    expect(result.databaseId, '35bdd41f-ce07-8152-92ae-dabdfc826f3b');
  });

  test('fetchStatus reads server-backed notion connection state', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'connected': true,
        'connection_id': 'connection-1',
        'database_id': 'database-1',
        'data_source_id': 'data-source-1',
        'database_title': 'Tasks',
        'database_url': 'https://www.notion.so/tasks',
        'last_synced_at': '2026-05-18T01:02:03+00:00',
        'last_successful_synced_at': '2026-05-18T01:02:03+00:00',
        'sync_status': 'success',
        'last_error_message': null,
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    final result = await service.fetchStatus();

    expect(apiClient.requests.single.path, '/integrations/notion/status');
    expect(result.connected, isTrue);
    expect(result.databaseId, 'database-1');
    expect(result.dataSourceId, 'data-source-1');
    expect(result.syncStatus, 'success');
    expect(result.lastSyncedAt, '2026-05-18T01:02:03+00:00');
    expect(
      result.lastSyncedAtDateTime,
      DateTime.parse('2026-05-18T01:02:03+00:00'),
    );
  });

  test('fetchStatus parses full snake_case fixture without nullable crashes', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'connected': false,
        'connection_id': 'connection-1',
        'database_id': 'database-1',
        'data_source_id': 'data-source-1',
        'database_title': 'Tasks',
        'database_url': 'https://www.notion.so/tasks',
        'last_synced_at': '2026-05-18T01:02:03+00:00',
        'last_successful_synced_at': '2026-05-18T01:03:03+00:00',
        'sync_status': 'disconnected',
        'last_error_message': 'Safe public message',
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    final result = await service.fetchStatus();

    expect(result.connected, isFalse);
    expect(result.connectionId, 'connection-1');
    expect(result.databaseId, 'database-1');
    expect(result.dataSourceId, 'data-source-1');
    expect(result.databaseTitle, 'Tasks');
    expect(result.databaseUrl, 'https://www.notion.so/tasks');
    expect(result.lastSyncedAt, '2026-05-18T01:02:03+00:00');
    expect(result.lastSuccessfulSyncedAt, '2026-05-18T01:03:03+00:00');
    expect(result.syncStatus, 'disconnected');
    expect(result.lastErrorMessage, 'Safe public message');
  });

  test('fetchStatus accepts null optional fields safely', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
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
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    final result = await service.fetchStatus();

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
    expect(result.lastSyncedAtDateTime, isNull);
    expect(result.lastSuccessfulSyncedAtDateTime, isNull);
  });

  test('datetime parsing policy keeps raw string and exposes optional DateTime getter', () async {
    final apiClient = _FakeNotionApiClient([
      _successData({
        'connected': true,
        'connection_id': 'connection-1',
        'database_id': 'database-1',
        'data_source_id': 'data-source-1',
        'database_title': 'Tasks',
        'database_url': 'https://www.notion.so/tasks',
        'last_synced_at': '2026-05-18T01:02:03Z',
        'last_successful_synced_at': 'invalid-date',
        'sync_status': 'success',
        'last_error_message': null,
      }),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    final result = await service.fetchStatus();

    expect(result.lastSyncedAt, '2026-05-18T01:02:03Z');
    expect(
      result.lastSyncedAtDateTime,
      DateTime.parse('2026-05-18T01:02:03Z'),
    );
    expect(result.lastSuccessfulSyncedAt, 'invalid-date');
    expect(result.lastSuccessfulSyncedAtDateTime, isNull);
  });

  test('disconnectConnection calls delete endpoint', () async {
    final apiClient = _FakeNotionApiClient([
      _successData(const <String, dynamic>{}),
    ]);
    final service = NotionSyncService(apiClient: apiClient);

    await service.disconnectConnection();

    expect(apiClient.requests.single.path, '/integrations/notion/connection');
  });

  testWidgets(
    'status loading does not show connected and server disconnected wins over local cache',
    (tester) async {
      final statusCompleter = Completer<NotionConnectionStatus>();
      final settingsStore = _FakeAppSettingsStore(
        const AppSettings(
          notificationsEnabled: true,
          vibrationEnabled: true,
          celebrationEffectEnabled: true,
          autoSaveEnabled: true,
          notionSyncEnabled: true,
          notionApiToken: 'cached-secret',
          notionDatabaseId: 'cached-db',
          notionDatabaseTitle: 'Cached DB',
        ),
      );
      final notionService = _FakeNotionSyncService(
        fetchStatusHandler: () => statusCompleter.future,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsStore: settingsStore,
            localDataStore: _FakeLocalDataStore(),
            notionSyncService: notionService,
          ),
        ),
      );

      final switchFinder = find.byKey(const Key('settings.notion.switch'));
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      expect(find.text('Notion 연결 상태 확인 중'), findsOneWidget);

      statusCompleter.complete(
        const NotionConnectionStatus(
          connected: false,
          databaseId: 'server-db',
          databaseTitle: 'Server DB',
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      expect(settingsStore.current.notionSyncEnabled, isFalse);
      expect(settingsStore.current.notionApiToken, 'cached-secret');
      expect(settingsStore.current.notionDatabaseId, 'cached-db');
      expect(settingsStore.current.notionDatabaseTitle, isEmpty);
    },
  );

  testWidgets('disconnect success clears local connection cache', (tester) async {
    final settingsStore = _FakeAppSettingsStore(
      const AppSettings(
        notificationsEnabled: true,
        vibrationEnabled: true,
        celebrationEffectEnabled: true,
        autoSaveEnabled: true,
        notionSyncEnabled: true,
        notionApiToken: 'cached-secret',
        notionDatabaseId: 'server-db',
        notionDatabaseTitle: 'Server DB',
      ),
    );
    final notionService = _FakeNotionSyncService(
      fetchStatusHandler: () async => const NotionConnectionStatus(
        connected: true,
        databaseId: 'server-db',
        databaseTitle: 'Server DB',
      ),
      disconnectHandler: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settingsStore: settingsStore,
          localDataStore: _FakeLocalDataStore(),
          notionSyncService: notionService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings.notion.disconnect')));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('settings.notion.switch'));
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(settingsStore.current.notionSyncEnabled, isFalse);
    expect(settingsStore.current.notionApiToken, 'cached-secret');
    expect(settingsStore.current.notionDatabaseId, 'server-db');
    expect(settingsStore.current.notionDatabaseTitle, isEmpty);
  });

  testWidgets('disconnect failure preserves existing local state', (tester) async {
    final settingsStore = _FakeAppSettingsStore(
      const AppSettings(
        notificationsEnabled: true,
        vibrationEnabled: true,
        celebrationEffectEnabled: true,
        autoSaveEnabled: true,
        notionSyncEnabled: true,
        notionApiToken: 'cached-secret',
        notionDatabaseId: 'server-db',
        notionDatabaseTitle: 'Server DB',
      ),
    );
    final notionService = _FakeNotionSyncService(
      fetchStatusHandler: () async => const NotionConnectionStatus(
        connected: true,
        databaseId: 'server-db',
        databaseTitle: 'Server DB',
      ),
      disconnectHandler: () async {
        throw const NotionSyncException('Disconnect failed');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settingsStore: settingsStore,
          localDataStore: _FakeLocalDataStore(),
          notionSyncService: notionService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings.notion.disconnect')));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('settings.notion.switch'));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(settingsStore.current.notionSyncEnabled, isTrue);
    expect(settingsStore.current.notionApiToken, 'cached-secret');
    expect(settingsStore.current.notionDatabaseId, 'server-db');
    expect(settingsStore.current.notionDatabaseTitle, 'Server DB');
  });

  testWidgets('status fetch failure shows retryable error state', (tester) async {
    final settingsStore = _FakeAppSettingsStore(
      const AppSettings(
        notificationsEnabled: true,
        vibrationEnabled: true,
        celebrationEffectEnabled: true,
        autoSaveEnabled: true,
        notionSyncEnabled: true,
        notionApiToken: 'cached-secret',
        notionDatabaseId: 'cached-db',
        notionDatabaseTitle: 'Cached DB',
      ),
    );
    final notionService = _FakeNotionSyncService(
      fetchStatusHandler: () async {
        throw const NotionSyncException('Server status unavailable');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settingsStore: settingsStore,
          localDataStore: _FakeLocalDataStore(),
          notionSyncService: notionService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('settings.notion.switch'));
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(find.text('Notion 연결 상태를 확인할 수 없어요'), findsOneWidget);
    expect(find.byKey(const Key('settings.notion.retry')), findsOneWidget);
  });
}

Map<String, dynamic> _successData(Map<String, dynamic> data) {
  return {'success': true, 'data': data, 'error': null};
}

class _FakeNotionApiClient extends ApiClient {
  _FakeNotionApiClient(this.responses) : super(baseUrl: 'http://localhost');

  final List<Object?> responses;
  final List<_CapturedRequest> requests = [];

  @override
  Future<ApiResponse<T>> postResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(path: path, body: body));
    return ApiResponse<T>.fromJson(responses.removeAt(0), parseData);
  }

  @override
  Future<ApiResponse<T>> getResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(path: path));
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
    return ApiResponse<T>.fromJson(responses.removeAt(0), parseData);
  }
}

class _CapturedRequest {
  const _CapturedRequest({required this.path, this.body});

  final String path;
  final Object? body;
}

class _FakeAppSettingsStore extends AppSettingsStore {
  _FakeAppSettingsStore(this.current);

  AppSettings current;

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
  }
}

class _FakeLocalDataStore extends LocalDataStore {
  @override
  Future<AppLocalData> load() async => AppLocalData.initial();

  @override
  Future<void> save(AppLocalData data) async {}
}

class _FakeNotionSyncService extends NotionSyncService {
  _FakeNotionSyncService({
    required Future<NotionConnectionStatus> Function() fetchStatusHandler,
    Future<void> Function()? disconnectHandler,
  }) : _fetchStatusHandler = fetchStatusHandler,
       _disconnectHandler = disconnectHandler,
       super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Future<NotionConnectionStatus> Function() _fetchStatusHandler;
  final Future<void> Function()? _disconnectHandler;

  @override
  Future<NotionConnectionStatus> fetchStatus() => _fetchStatusHandler();

  @override
  Future<void> disconnectConnection() async {
    if (_disconnectHandler != null) {
      await _disconnectHandler();
    }
  }

  @override
  void close() {}
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/models/quest_item.dart';
import 'package:start_on/pages/settings_screen.dart';
import 'package:start_on/services/api_client.dart';
import 'package:start_on/services/notion_sync_service.dart';
import 'package:start_on/storage/app_settings_store.dart';
import 'package:start_on/storage/local_data_store.dart';

void main() {
  testWidgets('initial checking state disables notion switch', (tester) async {
    final statusCompleter = Completer<NotionConnectionStatus>();
    final settingsStore = _FakeAppSettingsStore(_defaultSettings());
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

    expect(find.text('Notion 연결 상태 확인 중'), findsOneWidget);
    final switchWidget = tester.widget<Switch>(
      find.byKey(const Key('settings.notion.switch')),
    );
    expect(switchWidget.onChanged, isNull);

    statusCompleter.complete(const NotionConnectionStatus(connected: false));
    await tester.pumpAndSettle();
  });

  testWidgets('busy sync state disables action buttons', (tester) async {
    final syncCompleter = Completer<NotionSyncResult>();
    final settingsStore = _FakeAppSettingsStore(_defaultSettings());
    final notionService = _FakeNotionSyncService(
      fetchStatusHandler: () async => const NotionConnectionStatus(
        connected: true,
        databaseId: 'server-db',
        databaseTitle: 'Server DB',
      ),
      syncHandler: () => syncCompleter.future,
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

    await tester.tap(find.byKey(const Key('settings.notion.sync')));
    await tester.pump();

    final syncButton = tester.widget<FilledButton>(
      find.byKey(const Key('settings.notion.sync')),
    );
    final disconnectButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('settings.notion.disconnect')),
    );
    final switchWidget = tester.widget<Switch>(
      find.byKey(const Key('settings.notion.switch')),
    );

    expect(syncButton.onPressed, isNull);
    expect(disconnectButton.onPressed, isNull);
    expect(switchWidget.onChanged, isNull);

    syncCompleter.complete(
      const NotionSyncResult(
        databaseId: 'server-db',
        databaseTitle: 'Server DB',
        quests: <QuestItem>[],
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('sync clears temporary local notion quests', (tester) async {
    final settingsStore = _FakeAppSettingsStore(_defaultSettings());
    final localDataStore = _FakeLocalDataStore(
      AppLocalData.initial().copyWith(
        quests: [
          _quest(id: 'notion:page-1', title: 'Cached Notion'),
          _quest(id: 'manual-1', title: 'Manual'),
        ],
      ),
    );
    final notionService = _FakeNotionSyncService(
      fetchStatusHandler: () async => const NotionConnectionStatus(
        connected: true,
        databaseId: 'server-db',
        databaseTitle: 'Server DB',
      ),
      syncHandler: () async => NotionSyncResult(
        databaseId: 'server-db',
        databaseTitle: 'Server DB',
        quests: [_quest(id: 'notion:page-1', title: 'Response Notion')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settingsStore: settingsStore,
          localDataStore: localDataStore,
          notionSyncService: notionService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings.notion.sync')));
    await tester.pumpAndSettle();

    expect(localDataStore.current.quests.map((quest) => quest.id), [
      'manual-1',
    ]);
  });

  testWidgets('shows notion setup guidance copy', (tester) async {
    final settingsStore = _FakeAppSettingsStore(_defaultSettings());
    final notionService = _FakeNotionSyncService(
      fetchStatusHandler: () async =>
          const NotionConnectionStatus(connected: false),
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

    expect(find.text('빠른 설정 안내'), findsOneWidget);
    expect(find.textContaining('Notion Dev Page에서 connection'), findsOneWidget);
    expect(find.textContaining('시크릿 토큰'), findsOneWidget);
    expect(find.textContaining('생성한 connection을 연결'), findsOneWidget);
    expect(find.textContaining('/p/와 ?v 사이'), findsOneWidget);
    expect(find.byKey(const Key('settings.notion.token')), findsOneWidget);
    expect(find.byKey(const Key('settings.notion.database')), findsOneWidget);
  });
}

QuestItem _quest({required String id, required String title}) {
  return QuestItem(
    id: id,
    title: title,
    exp: 50,
    difficulty: '보통',
    category: 'work',
    elapsedSeconds: 0,
    defaultDurationSeconds: 25 * 60,
  );
}

AppSettings _defaultSettings() {
  return const AppSettings(
    notificationsEnabled: true,
    vibrationEnabled: true,
    celebrationEffectEnabled: true,
    autoSaveEnabled: true,
    notionSyncEnabled: true,
    notionApiToken: 'cached-secret',
    notionDatabaseId: 'cached-db',
    notionDatabaseTitle: 'Cached DB',
  );
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
  _FakeLocalDataStore([AppLocalData? current])
    : current = current ?? AppLocalData.initial();

  AppLocalData current;

  @override
  Future<AppLocalData> load() async => current;

  @override
  Future<void> save(AppLocalData data) async {
    current = data;
  }
}

class _FakeNotionSyncService extends NotionSyncService {
  _FakeNotionSyncService({
    required Future<NotionConnectionStatus> Function() fetchStatusHandler,
    Future<void> Function()? disconnectHandler,
    Future<NotionSyncResult> Function()? syncHandler,
  }) : _fetchStatusHandler = fetchStatusHandler,
       _disconnectHandler = disconnectHandler,
       _syncHandler = syncHandler,
       super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Future<NotionConnectionStatus> Function() _fetchStatusHandler;
  final Future<void> Function()? _disconnectHandler;
  final Future<NotionSyncResult> Function()? _syncHandler;

  @override
  Future<NotionConnectionStatus> fetchStatus() => _fetchStatusHandler();

  @override
  Future<void> disconnectConnection() async {
    if (_disconnectHandler != null) {
      await _disconnectHandler();
    }
  }

  @override
  Future<NotionSyncResult> syncSavedConnection() async {
    if (_syncHandler != null) {
      return _syncHandler();
    }
    return const NotionSyncResult(
      databaseId: 'server-db',
      databaseTitle: 'Server DB',
      quests: <QuestItem>[],
    );
  }

  @override
  void close() {}
}

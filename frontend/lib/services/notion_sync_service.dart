import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/quest_category.dart';
import 'package:start_on/models/quest_item.dart';
import 'package:start_on/services/api_client.dart';

const String _notionConnectPath = '/integrations/notion/connect';
const String _notionSyncPath = '/integrations/notion/sync';
const String _notionStatusPath = '/integrations/notion/status';
const String _notionDisconnectPath = '/integrations/notion/connection';

class NotionSyncConfig {
  const NotionSyncConfig({required this.apiToken, required this.databaseInput});

  final String apiToken;
  final String databaseInput;
}

class NotionSyncResult {
  const NotionSyncResult({
    required this.databaseId,
    required this.databaseTitle,
    required this.quests,
  });

  final String databaseId;
  final String databaseTitle;
  final List<QuestItem> quests;
}

class NotionConnectionStatus {
  const NotionConnectionStatus({
    required this.connected,
    this.connectionId,
    this.databaseId,
    this.dataSourceId,
    this.databaseTitle,
    this.databaseUrl,
    this.lastSyncedAt,
    this.lastSuccessfulSyncedAt,
    this.syncStatus,
    this.lastErrorMessage,
  });

  final bool connected;
  final String? connectionId;
  final String? databaseId;
  final String? dataSourceId;
  final String? databaseTitle;
  final String? databaseUrl;
  final String? lastSyncedAt;
  final String? lastSuccessfulSyncedAt;
  final String? syncStatus;
  final String? lastErrorMessage;

  DateTime? get lastSyncedAtDateTime => _tryParseIso8601(lastSyncedAt);
  DateTime? get lastSuccessfulSyncedAtDateTime =>
      _tryParseIso8601(lastSuccessfulSyncedAt);
}

class NotionSyncException implements Exception {
  const NotionSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotionSyncService {
  NotionSyncService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient.authenticated(),
      _ownsApiClient = apiClient == null;

  final ApiClient _apiClient;
  final bool _ownsApiClient;

  Future<NotionSyncResult> syncDatabase(NotionSyncConfig config) async {
    final trimmedToken = config.apiToken.trim();
    final trimmedInput = config.databaseInput.trim();
    final inputId = normalizeDatabaseId(trimmedInput);

    if (trimmedToken.isEmpty) {
      throw const NotionSyncException(
        'Notion 토큰을 입력해 주세요.',
      );
    }
    if (inputId.isEmpty) {
      throw const NotionSyncException(
        '올바른 Notion 데이터베이스 URL, 데이터 소스 ID, 또는 데이터베이스 ID를 입력해 주세요.',
      );
    }

    await _connect(
      apiToken: trimmedToken,
      databaseInput: trimmedInput,
      normalizedInputId: inputId,
    );
    return syncSavedConnection();
  }

  Future<NotionSyncResult> syncSavedConnection() async {
    final response = await _request(
      () => _apiClient.postResponse<_NotionSyncResponse>(
        _notionSyncPath,
        parseData: _NotionSyncResponse.fromJson,
        body: const <String, dynamic>{},
      ),
    );
    return _requireData(
      response,
      message: 'The server did not return a Notion sync result.',
    ).toResult();
  }

  Future<NotionConnectionStatus> fetchStatus() async {
    final response = await _request(
      () => _apiClient.getResponse<NotionConnectionStatus>(
        _notionStatusPath,
        parseData: NotionConnectionStatusParser.fromJson,
      ),
    );
    return _requireData(
      response,
      message: 'The server did not return Notion connection status.',
    );
  }

  Future<void> disconnectConnection() async {
    final response = await _request(
      () => _apiClient.deleteResponse<Object?>(
        _notionDisconnectPath,
        parseData: (json) => json,
      ),
    );
    if (!response.success) {
      throw NotionSyncException(
        response.error?.message ?? 'Failed to disconnect Notion.',
      );
    }
  }

  void close() {
    if (_ownsApiClient) {
      _apiClient.close();
    }
  }

  Future<_NotionConnectResponse> _connect({
    required String apiToken,
    required String databaseInput,
    required String normalizedInputId,
  }) async {
    final response = await _request(
      () => _apiClient.postResponse<_NotionConnectResponse>(
        _notionConnectPath,
        parseData: _NotionConnectResponse.fromJson,
        body: _connectRequestBody(
          apiToken: apiToken,
          databaseInput: databaseInput,
          normalizedInputId: normalizedInputId,
        ),
      ),
    );

    return _requireData(
      response,
      message: 'The server did not return a Notion connection result.',
    );
  }

  Map<String, dynamic> _connectRequestBody({
    required String apiToken,
    required String databaseInput,
    required String normalizedInputId,
  }) {
    final body = <String, dynamic>{'notion_api_token': apiToken};
    final uri = Uri.tryParse(databaseInput);
    final isUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (isUrl) {
      body['database_url'] = databaseInput;
    } else {
      body['data_source_id'] = normalizedInputId;
    }
    return body;
  }

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiClientException catch (error) {
      throw NotionSyncException(_describeApiError(error));
    } on FormatException {
      throw const NotionSyncException(
        '서버에서 올바르지 않은 Notion 응답을 반환했어요.',
      );
    }
  }

  T _requireData<T>(ApiResponse<T> response, {required String message}) {
    final data = response.data;
    if (response.success && data != null) {
      return data;
    }

    final error = response.error;
    throw NotionSyncException(error?.message ?? message);
  }

  String _describeApiError(ApiClientException error) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    if (error.statusCode == 401) {
      return '다시 로그인한 뒤 시도해 주세요.';
    }
    if (error.statusCode == 403) {
      return 'Notion 접근이 거부되었어요. Integration 권한을 확인한 뒤 다시 시도해 주세요.';
    }
    if (error.statusCode == 404) {
      return '선택한 Notion 데이터베이스 또는 데이터 소스를 찾을 수 없어요.';
    }
    if (error.code == 'network_error') {
      return '서버에 연결할 수 없어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.';
    }
    if (error.code == 'request_timeout') {
      return '서버 응답이 너무 오래 걸렸어요. 다시 시도해 주세요.';
    }
    return 'Notion 요청에 실패했어요. 다시 시도해 주세요.';
  }

  static String normalizeDatabaseId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final match = RegExp(
      r'[0-9a-fA-F]{8}(?:-?[0-9a-fA-F]{4}){3}-?[0-9a-fA-F]{12}',
    ).firstMatch(trimmed);
    if (match == null) {
      return '';
    }

    final compact = match.group(0)!.replaceAll('-', '');
    return [
      compact.substring(0, 8),
      compact.substring(8, 12),
      compact.substring(12, 16),
      compact.substring(16, 20),
      compact.substring(20, 32),
    ].join('-');
  }
}

class NotionConnectionStatusParser {
  static NotionConnectionStatus fromJson(Object? json) {
    final object = _asJsonObject(json, 'Notion status must be an object.');
    return NotionConnectionStatus(
      connected: _readRequiredBool(object, 'connected'),
      connectionId: _readOptionalString(object, 'connection_id'),
      databaseId: _readOptionalString(object, 'database_id'),
      dataSourceId: _readOptionalString(object, 'data_source_id'),
      databaseTitle: _readOptionalString(object, 'database_title'),
      databaseUrl: _readOptionalString(object, 'database_url'),
      lastSyncedAt: _readOptionalString(object, 'last_synced_at'),
      lastSuccessfulSyncedAt: _readOptionalString(
        object,
        'last_successful_synced_at',
      ),
      syncStatus: _readOptionalString(object, 'sync_status'),
      lastErrorMessage: _readOptionalString(object, 'last_error_message'),
    );
  }
}

DateTime? _tryParseIso8601(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return DateTime.tryParse(trimmed);
}

class _NotionConnectResponse {
  const _NotionConnectResponse({
    required this.connectionId,
    required this.databaseId,
    required this.databaseTitle,
    required this.syncStatus,
  });

  factory _NotionConnectResponse.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Notion connection must be an object.');
    return _NotionConnectResponse(
      connectionId: _readRequiredString(object, 'connection_id'),
      databaseId: _readRequiredString(object, 'database_id'),
      databaseTitle: _readRequiredString(object, 'database_title'),
      syncStatus: _readRequiredString(object, 'sync_status'),
    );
  }

  final String connectionId;
  final String databaseId;
  final String databaseTitle;
  final String syncStatus;
}

class _NotionSyncResponse {
  const _NotionSyncResponse({
    required this.databaseId,
    required this.databaseTitle,
    required this.quests,
  });

  factory _NotionSyncResponse.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Notion sync result must be an object.');
    final rawQuests = object['quests'] as List<dynamic>? ?? const [];
    return _NotionSyncResponse(
      databaseId: _readRequiredString(object, 'database_id'),
      databaseTitle: _readRequiredString(object, 'database_title'),
      quests: rawQuests.map(_NotionQuestCandidate.fromJson).toList(),
    );
  }

  final String databaseId;
  final String databaseTitle;
  final List<_NotionQuestCandidate> quests;

  NotionSyncResult toResult() {
    return NotionSyncResult(
      databaseId: databaseId,
      databaseTitle: databaseTitle,
      quests: [
        for (var index = 0; index < quests.length; index++)
          quests[index].toQuestItem(databaseId: databaseId, index: index),
      ],
    );
  }
}

class _NotionQuestCandidate {
  const _NotionQuestCandidate({
    required this.title,
    required this.difficulty,
    required this.category,
    required this.exp,
    required this.defaultDurationSeconds,
    this.externalId,
  });

  factory _NotionQuestCandidate.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Notion quest must be an object.');
    return _NotionQuestCandidate(
      title: _readRequiredString(object, 'title'),
      difficulty: _readRequiredString(object, 'difficulty'),
      category: _readRequiredString(object, 'category'),
      exp: _readInt(object, 'exp'),
      defaultDurationSeconds: _readInt(object, 'defaultDurationSeconds'),
      externalId: _readOptionalString(object, 'external_id'),
    );
  }

  final String title;
  final String difficulty;
  final String category;
  final int exp;
  final int defaultDurationSeconds;
  final String? externalId;

  QuestItem toQuestItem({required String databaseId, required int index}) {
    final stableId =
        externalId == null || externalId!.trim().isEmpty
        ? '$databaseId:$index:$title'
        : externalId!;
    return QuestItem(
      id: 'notion:${Uri.encodeComponent(stableId)}',
      title: title,
      exp: exp,
      difficulty: questDifficultyFromApi(difficulty),
      category: normalizeQuestCategory(category),
      elapsedSeconds: 0,
      defaultDurationSeconds: defaultDurationSeconds,
    );
  }
}

Map<String, dynamic> _asJsonObject(Object? value, String message) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  throw FormatException(message);
}

String _readRequiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('$key must be a non-empty string.');
}

String? _readOptionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _readRequiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

int _readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('$key must be a number.');
}

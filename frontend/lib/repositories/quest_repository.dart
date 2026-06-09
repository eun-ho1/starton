import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/services/api_client.dart';

class QuestRepository {
  QuestRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient.authenticated(),
      _ownsApiClient = apiClient == null;

  final ApiClient _apiClient;
  final bool _ownsApiClient;

  Future<List<QuestItemResponse>> listQuests() async {
    final response = await _apiClient.getResponse<List<QuestItemResponse>>(
      '/quests',
      parseData: _parseQuestList,
    );

    return _requireData(
      response,
      code: 'missing_quest_list',
      message: 'Server response did not include a quest list.',
    );
  }

  Future<QuestItemResponse> createQuest(QuestCreateRequest request) async {
    final response = await _apiClient.postResponse<QuestItemResponse>(
      '/quests',
      body: request.toJson(),
      parseData: QuestItemResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_created_quest',
      message: 'Server response did not include the created quest.',
    );
  }

  Future<QuestItemResponse> updateQuest(
    String questId,
    QuestUpdateRequest request,
  ) async {
    final response = await _apiClient.patchResponse<QuestItemResponse>(
      _questPath(questId),
      body: request.toJson(),
      parseData: QuestItemResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_updated_quest',
      message: 'Server response did not include the updated quest.',
    );
  }

  Future<void> deleteQuest(String questId) async {
    final response = await _apiClient.deleteResponse<Object>(
      _questPath(questId),
      parseData: (json) => json ?? const <String, dynamic>{},
    );

    _requireSuccess(response);
  }

  Future<CompletedQuestRecordResponse> completeQuest(
    String questId, {
    required int elapsedSeconds,
    String? proofImagePath,
  }) async {
    final response = await _apiClient
        .postResponse<CompletedQuestRecordResponse>(
          '${_questPath(questId)}/complete',
          body: QuestCompleteRequest(
            elapsedSeconds: elapsedSeconds,
            proofImagePath: proofImagePath,
          ).toJson(),
          parseData: CompletedQuestRecordResponse.fromJson,
        );

    return _requireData(
      response,
      code: 'missing_completed_quest',
      message: 'Server response did not include the completed quest record.',
    );
  }

  Future<QuestItemResponse> undoCompleteQuest(String questId) async {
    final response = await _apiClient.postResponse<QuestItemResponse>(
      '${_questPath(questId)}/undo-complete',
      body: const <String, dynamic>{},
      parseData: QuestItemResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_restored_quest',
      message: 'Server response did not include the restored quest.',
    );
  }

  void close() {
    if (_ownsApiClient) {
      _apiClient.close();
    }
  }

  String _questPath(String questId) =>
      '/quests/${Uri.encodeComponent(questId)}';

  List<QuestItemResponse> _parseQuestList(Object? json) {
    if (json is! List) {
      throw const FormatException('Quest list must be a JSON array.');
    }
    return json.map(QuestItemResponse.fromJson).toList();
  }

  T _requireData<T>(
    ApiResponse<T> response, {
    required String code,
    required String message,
  }) {
    final data = response.data;
    if (response.success && data != null) {
      return data;
    }

    final error = response.error;
    throw QuestRepositoryException(
      code: error?.code ?? code,
      message: error?.message ?? message,
    );
  }

  void _requireSuccess(ApiResponse<Object> response) {
    if (response.success) {
      return;
    }

    final error = response.error;
    throw QuestRepositoryException(
      code: error?.code ?? 'quest_request_failed',
      message: error?.message ?? 'Quest request failed.',
    );
  }
}

class QuestRepositoryException implements Exception {
  const QuestRepositoryException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'QuestRepositoryException($code): $message';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/repositories/quest_repository.dart';
import 'package:start_on/services/api_client.dart';

void main() {
  test('listQuests calls protected quest list endpoint', () async {
    final apiClient = _FakeQuestApiClient(
      ApiResponse<List<QuestItemResponse>>(
        success: true,
        data: [_quest()],
        error: null,
      ),
    );
    final repository = QuestRepository(apiClient: apiClient);

    final quests = await repository.listQuests();

    expect(apiClient.requests.single.method, 'GET');
    expect(apiClient.requests.single.path, '/quests');
    expect(quests.single.id, 'quest-1');
  });

  test('createQuest posts create request body', () async {
    final apiClient = _FakeQuestApiClient(
      ApiResponse<QuestItemResponse>(
        success: true,
        data: _quest(title: 'Created quest'),
        error: null,
      ),
    );
    final repository = QuestRepository(apiClient: apiClient);

    final created = await repository.createQuest(
      QuestCreateRequest(
        title: ' Created quest ',
        exp: 50,
        difficulty: 'normal',
        category: 'work',
        defaultDurationSeconds: 2700,
        dueAt: DateTime(2026, 6, 2),
      ),
    );

    expect(apiClient.requests.single.method, 'POST');
    expect(apiClient.requests.single.path, '/quests');
    expect(apiClient.requests.single.body, {
      'title': 'Created quest',
      'exp': 50,
      'difficulty': 'normal',
      'category': 'work',
      'defaultDurationSeconds': 2700,
      'due_at': '2026-06-02T00:00:00.000',
    });
    expect(created.title, 'Created quest');
  });

  test('updateQuest patches update request body', () async {
    final apiClient = _FakeQuestApiClient(
      ApiResponse<QuestItemResponse>(
        success: true,
        data: _quest(title: 'Updated quest', elapsedSeconds: 120),
        error: null,
      ),
    );
    final repository = QuestRepository(apiClient: apiClient);

    final updated = await repository.updateQuest(
      'quest-1',
      QuestUpdateRequest(
        title: 'Updated quest',
        exp: 80,
        difficulty: 'hard',
        category: 'study',
        elapsedSeconds: 120,
        defaultDurationSeconds: 5400,
        dueAt: DateTime(2026, 6, 3),
      ),
    );

    expect(apiClient.requests.single.method, 'PATCH');
    expect(apiClient.requests.single.path, '/quests/quest-1');
    expect(apiClient.requests.single.body, {
      'title': 'Updated quest',
      'exp': 80,
      'difficulty': 'hard',
      'category': 'study',
      'elapsedSeconds': 120,
      'defaultDurationSeconds': 5400,
      'due_at': '2026-06-03T00:00:00.000',
    });
    expect(updated.elapsedSeconds, 120);
  });

  test('deleteQuest calls delete endpoint', () async {
    final apiClient = _FakeQuestApiClient(
      const ApiResponse<Object>(
        success: true,
        data: <String, dynamic>{},
        error: null,
      ),
    );
    final repository = QuestRepository(apiClient: apiClient);

    await repository.deleteQuest('quest-1');

    expect(apiClient.requests.single.method, 'DELETE');
    expect(apiClient.requests.single.path, '/quests/quest-1');
  });

  test('completeQuest posts completion request body', () async {
    final apiClient = _FakeQuestApiClient(
      const ApiResponse<CompletedQuestRecordResponse>(
        success: true,
        data: CompletedQuestRecordResponse(
          questId: 'quest-1',
          title: 'Completed quest',
          difficulty: 'normal',
          category: 'work',
          earnedExp: 30,
          completedAt: '2026-05-09T11:00:00+09:00',
          elapsedSeconds: 1800,
          proofImagePath: '/proofs/quest.png',
        ),
        error: null,
      ),
    );
    final repository = QuestRepository(apiClient: apiClient);

    final completed = await repository.completeQuest(
      'quest-1',
      elapsedSeconds: 1800,
      proofImagePath: '/proofs/quest.png',
    );

    expect(apiClient.requests.single.method, 'POST');
    expect(apiClient.requests.single.path, '/quests/quest-1/complete');
    expect(apiClient.requests.single.body, {
      'elapsedSeconds': 1800,
      'proofImagePath': '/proofs/quest.png',
    });
    expect(completed.earnedExp, 30);
  });

  test('throws repository exception when response has no data', () async {
    final apiClient = _FakeQuestApiClient(
      const ApiResponse<QuestItemResponse>(
        success: true,
        data: null,
        error: null,
      ),
    );
    final repository = QuestRepository(apiClient: apiClient);

    expect(
      () => repository.createQuest(
        const QuestCreateRequest(
          title: 'Quest',
          exp: 50,
          difficulty: 'normal',
          category: 'work',
          defaultDurationSeconds: 2700,
        ),
      ),
      throwsA(isA<QuestRepositoryException>()),
    );
  });
}

QuestItemResponse _quest({String title = 'Quest', int elapsedSeconds = 0}) {
  return QuestItemResponse(
    id: 'quest-1',
    title: title,
    exp: 50,
    difficulty: 'normal',
    category: 'work',
    elapsedSeconds: elapsedSeconds,
    defaultDurationSeconds: 2700,
    dueAt: null,
  );
}

class _FakeQuestApiClient extends ApiClient {
  _FakeQuestApiClient(this.response) : super(baseUrl: 'http://localhost');

  final ApiResponse<dynamic> response;
  final List<_CapturedRequest> requests = [];

  @override
  Future<ApiResponse<T>> getResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(method: 'GET', path: path));
    return response as ApiResponse<T>;
  }

  @override
  Future<ApiResponse<T>> postResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(method: 'POST', path: path, body: body));
    return response as ApiResponse<T>;
  }

  @override
  Future<ApiResponse<T>> patchResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(method: 'PATCH', path: path, body: body));
    return response as ApiResponse<T>;
  }

  @override
  Future<ApiResponse<T>> deleteResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(method: 'DELETE', path: path, body: body));
    return response as ApiResponse<T>;
  }
}

class _CapturedRequest {
  const _CapturedRequest({required this.method, required this.path, this.body});

  final String method;
  final String path;
  final Object? body;
}

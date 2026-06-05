import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/task_intake_api_models.dart';
import 'package:start_on/repositories/task_intake_repository.dart';
import 'package:start_on/services/api_client.dart';

void main() {
  test('createIntake posts request body to task intake endpoint', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      ApiResponse<TaskIntakeResponse>(
        success: true,
        data: _intakeResponse(),
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    final response = await repository.createIntake(
      const TaskIntakeRequest(
        text: '  내일 컴비전 과제 해야 함  ',
        userContext: TaskIntakeUserContext(energyNow: 'medium'),
      ),
    );

    expect(apiClient.requests.single.method, 'POST');
    expect(apiClient.requests.single.path, '/task-intake');
    expect(apiClient.requests.single.body, {
      'text': '내일 컴비전 과제 해야 함',
      'source': 'manual',
      'client_timezone': 'Asia/Seoul',
      'user_context': {
        'energy_now': 'medium',
        'available_minutes_today': null,
        'extra': <String, dynamic>{},
      },
      'client_metadata': <String, dynamic>{},
    });
    expect(response.candidateId, 'candidate-1');
  });

  test('listTasks loads active tasks endpoint', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      ApiResponse<List<TaskResponse>>(
        success: true,
        data: [_commitResult().task],
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    final tasks = await repository.listTasks();

    expect(apiClient.requests.single.method, 'GET');
    expect(apiClient.requests.single.path, '/tasks');
    expect(tasks.single.id, 'task-1');
  });

  test('getCandidate calls encoded task candidate endpoint', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      ApiResponse<TaskCandidateResponse>(
        success: true,
        data: _candidate(),
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    final candidate = await repository.getCandidate('candidate/1');

    expect(apiClient.requests.single.method, 'GET');
    expect(apiClient.requests.single.path, '/task-candidates/candidate%2F1');
    expect(candidate.title, '컴퓨터비전 과제 제출 준비');
  });

  test('confirmCandidate posts selection to confirm endpoint', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      ApiResponse<TaskCommitResultResponse>(
        success: true,
        data: _commitResult(),
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    final response = await repository.confirmCandidate(
      'candidate/1',
      const TaskConfirmRequest(
        selectedSubtaskIds: ['subtask-1'],
        selectedReminderIds: ['reminder-1'],
      ),
    );

    expect(apiClient.requests.single.method, 'POST');
    expect(
      apiClient.requests.single.path,
      '/task-candidates/candidate%2F1/confirm',
    );
    expect(apiClient.requests.single.body, {
      'accepted': true,
      'edited_fields': <String, dynamic>{},
      'selected_subtask_ids': ['subtask-1'],
      'selected_reminder_ids': ['reminder-1'],
    });
    expect(response.task.id, 'task-1');
  });

  test('reviseCandidate posts revision request to revise endpoint', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      ApiResponse<TaskCandidateResponse>(
        success: true,
        data: _candidate(),
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    await repository.reviseCandidate(
      'candidate-1',
      const TaskCandidateReviseRequest(revisionType: 'make_smaller'),
    );

    expect(apiClient.requests.single.method, 'POST');
    expect(
      apiClient.requests.single.path,
      '/task-candidates/candidate-1/revise',
    );
    expect(apiClient.requests.single.body, {
      'revision_type': 'make_smaller',
      'edited_fields': <String, dynamic>{},
      'note': null,
    });
  });

  test('rejectCandidate posts reject reason to reject endpoint', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      ApiResponse<TaskCandidateResponse>(
        success: true,
        data: _candidate(),
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    await repository.rejectCandidate(
      'candidate-1',
      const TaskCandidateRejectRequest(reason: 'cancelled_from_review'),
    );

    expect(apiClient.requests.single.method, 'POST');
    expect(
      apiClient.requests.single.path,
      '/task-candidates/candidate-1/reject',
    );
    expect(apiClient.requests.single.body, {'reason': 'cancelled_from_review'});
  });

  test('throws repository exception when response has no data', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      const ApiResponse<TaskIntakeResponse>(
        success: true,
        data: null,
        error: null,
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    expect(
      () => repository.createIntake(const TaskIntakeRequest(text: '할 일')),
      throwsA(isA<TaskIntakeRepositoryException>()),
    );
  });

  test('throws repository exception with server error detail', () async {
    final apiClient = _FakeTaskIntakeApiClient(
      const ApiResponse<TaskIntakeResponse>(
        success: false,
        data: null,
        error: ApiError(
          code: 'invalid_task_intake_request',
          message: 'text must not be empty.',
        ),
      ),
    );
    final repository = TaskIntakeRepository(apiClient: apiClient);

    expect(
      () => repository.createIntake(const TaskIntakeRequest(text: '')),
      throwsA(
        isA<TaskIntakeRepositoryException>()
            .having(
              (error) => error.code,
              'code',
              'invalid_task_intake_request',
            )
            .having(
              (error) => error.message,
              'message',
              'text must not be empty.',
            ),
      ),
    );
  });
}

TaskIntakeResponse _intakeResponse() {
  return TaskIntakeResponse(
    rawInputId: 'raw-1',
    candidateId: 'candidate-1',
    status: 'candidate_ready',
    candidate: _candidate(),
  );
}

TaskCandidateResponse _candidate() {
  return const TaskCandidateResponse(
    id: 'candidate-1',
    userId: 'user-1',
    rawInputId: 'raw-1',
    mediatorRunId: 'run-1',
    title: '컴퓨터비전 과제 제출 준비',
    description: null,
    dueAt: null,
    priority: 'high',
    estimatedMinutes: 120,
    energyRequired: 'medium',
    difficulty: 'high',
    nextAction: '과제 파일 열기',
    recommendedToday: true,
    todayReason: '오늘은 첫 단계만 진행',
    overloadWarning: null,
    confidence: 0.82,
    status: 'draft',
    modelPayload: <String, dynamic>{},
    subtasks: <CandidateSubtaskResponse>[],
    reminders: <CandidateReminderResponse>[],
    createdAt: null,
    updatedAt: null,
  );
}

TaskCommitResultResponse _commitResult() {
  return const TaskCommitResultResponse(
    candidateId: 'candidate-1',
    task: TaskResponse(
      id: 'task-1',
      userId: 'user-1',
      candidateId: 'candidate-1',
      rawInputId: 'raw-1',
      mediatorRunId: 'run-1',
      title: '컴퓨터비전 과제 제출 준비',
      description: null,
      status: 'todo',
      priority: 'high',
      dueAt: null,
      estimatedMinutes: 120,
      energyRequired: 'medium',
      difficulty: 'high',
      nextAction: '과제 파일 열기',
      source: 'ai',
      metadata: <String, dynamic>{},
      subtasks: <SubtaskResponse>[],
      reminders: <ReminderResponse>[],
      createdAt: null,
      updatedAt: null,
      completedAt: null,
    ),
  );
}

class _FakeTaskIntakeApiClient extends ApiClient {
  _FakeTaskIntakeApiClient(this.response) : super(baseUrl: 'http://localhost');

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
}

class _CapturedRequest {
  const _CapturedRequest({required this.method, required this.path, this.body});

  final String method;
  final String path;
  final Object? body;
}

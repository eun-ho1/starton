import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/models/task_intake_api_models.dart';
import 'package:start_on/services/api_client.dart';

class TaskIntakeRepository {
  static const Duration aiRequestTimeout = Duration(seconds: 75);

  TaskIntakeRepository({ApiClient? apiClient})
    : _apiClient =
          apiClient ?? ApiClient.authenticated(timeout: aiRequestTimeout),
      _ownsApiClient = apiClient == null;

  final ApiClient _apiClient;
  final bool _ownsApiClient;

  Future<TaskIntakeResponse> createIntake(TaskIntakeRequest request) async {
    final response = await _apiClient.postResponse<TaskIntakeResponse>(
      '/task-intake',
      body: request.toJson(),
      parseData: TaskIntakeResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_task_intake',
      message: 'Server response did not include task intake data.',
    );
  }

  Future<List<TaskResponse>> listTasks() async {
    final response = await _apiClient.getResponse<List<TaskResponse>>(
      '/tasks',
      parseData: _parseTaskList,
    );

    return _requireData(
      response,
      code: 'missing_task_list',
      message: 'Server response did not include a task list.',
    );
  }

  Future<TaskCandidateResponse> getCandidate(String candidateId) async {
    final response = await _apiClient.getResponse<TaskCandidateResponse>(
      _candidatePath(candidateId),
      parseData: TaskCandidateResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_task_candidate',
      message: 'Server response did not include task candidate data.',
    );
  }

  Future<TaskCommitResultResponse> confirmCandidate(
    String candidateId,
    TaskConfirmRequest request,
  ) async {
    final response = await _apiClient.postResponse<TaskCommitResultResponse>(
      _candidateActionPath(candidateId, 'confirm'),
      body: request.toJson(),
      parseData: TaskCommitResultResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_task_commit_result',
      message: 'Server response did not include committed task data.',
    );
  }

  Future<TaskCandidateResponse> reviseCandidate(
    String candidateId,
    TaskCandidateReviseRequest request,
  ) async {
    final response = await _apiClient.postResponse<TaskCandidateResponse>(
      _candidateActionPath(candidateId, 'revise'),
      body: request.toJson(),
      parseData: TaskCandidateResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_task_candidate',
      message: 'Server response did not include revised task candidate data.',
    );
  }

  Future<TaskCandidateResponse> rejectCandidate(
    String candidateId,
    TaskCandidateRejectRequest request,
  ) async {
    final response = await _apiClient.postResponse<TaskCandidateResponse>(
      _candidateActionPath(candidateId, 'reject'),
      body: request.toJson(),
      parseData: TaskCandidateResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_task_candidate',
      message: 'Server response did not include rejected task candidate data.',
    );
  }

  Future<TaskResponse> updateTaskProgress(
    String taskId, {
    required int elapsedSeconds,
  }) async {
    final response = await _apiClient.patchResponse<TaskResponse>(
      '/tasks/${Uri.encodeComponent(taskId)}/progress',
      body: {'elapsed_seconds': elapsedSeconds < 0 ? 0 : elapsedSeconds},
      parseData: TaskResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_updated_task',
      message: 'Server response did not include the updated task.',
    );
  }

  Future<CompletedQuestRecordResponse> completeTask(
    String taskId, {
    required int elapsedSeconds,
    String? proofImagePath,
  }) async {
    final response = await _apiClient
        .postResponse<CompletedQuestRecordResponse>(
          '/tasks/${Uri.encodeComponent(taskId)}/complete',
          body: QuestCompleteRequest(
            elapsedSeconds: elapsedSeconds,
            proofImagePath: proofImagePath,
          ).toJson(),
          parseData: CompletedQuestRecordResponse.fromJson,
        );

    return _requireData(
      response,
      code: 'missing_completed_task',
      message: 'Server response did not include the completed task record.',
    );
  }

  void close() {
    if (_ownsApiClient) {
      _apiClient.close();
    }
  }

  List<TaskResponse> _parseTaskList(Object? json) {
    if (json is! List) {
      throw const FormatException('Task list must be a JSON array.');
    }
    return json.map(TaskResponse.fromJson).toList();
  }

  String _candidatePath(String candidateId) =>
      '/task-candidates/${Uri.encodeComponent(candidateId)}';

  String _candidateActionPath(String candidateId, String action) =>
      '${_candidatePath(candidateId)}/$action';

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
    throw TaskIntakeRepositoryException(
      code: error?.code ?? code,
      message: error?.message ?? message,
    );
  }
}

class TaskIntakeRepositoryException implements Exception {
  const TaskIntakeRepositoryException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'TaskIntakeRepositoryException($code): $message';
}

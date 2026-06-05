import "package:start_on/models/app_local_data.dart";
import "package:start_on/models/task_intake_api_models.dart";

QuestItem questItemFromTaskResponse(
  TaskResponse task, {
  required QuestItem fallbackDraft,
}) {
  final difficulty = _questDifficultyFromTaskResponse(task.difficulty);
  final category =
      _metadataString(task.metadata, "category") ??
      _nestedMetadataString(task.metadata, "client_metadata", "category") ??
      _nestedMetadataString(task.metadata, "edited_fields", "category") ??
      fallbackDraft.category;
  final elapsedSeconds =
      task.elapsedSeconds ??
      _metadataInt(task.metadata, "elapsed_seconds") ??
      _metadataInt(task.metadata, "elapsedSeconds") ??
      _nestedMetadataInt(task.metadata, "client_metadata", "elapsed_seconds") ??
      _nestedMetadataInt(task.metadata, "client_metadata", "elapsedSeconds") ??
      fallbackDraft.elapsedSeconds;

  return QuestItem(
    id: task.id,
    title: task.title,
    exp:
        _metadataInt(task.metadata, "exp") ??
        _nestedMetadataInt(task.metadata, "client_metadata", "exp") ??
        fallbackDraft.exp,
    difficulty: difficulty,
    category: normalizeQuestCategory(category),
    elapsedSeconds: elapsedSeconds,
    defaultDurationSeconds: _taskDurationSecondsFromTaskResponse(
      task,
      difficulty: difficulty,
      fallbackDraft: fallbackDraft,
    ),
    dueDate: normalizeQuestDueDate(task.dueAt ?? fallbackDraft.dueDate),
    subtasks: _questSubtasksFromTaskResponse(task.subtasks),
    activeSubtaskId: _firstIncompleteTaskSubtaskId(task.subtasks),
    syncTarget: questSyncTargetTask,
  );
}

List<QuestSubtask> _questSubtasksFromTaskResponse(
  List<SubtaskResponse> subtasks,
) {
  final sortedSubtasks = [...subtasks]
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  return sortedSubtasks
      .map(
        (subtask) => QuestSubtask(
          id: subtask.id,
          title: subtask.title,
          orderIndex: subtask.orderIndex,
          estimatedMinutes: subtask.estimatedMinutes,
          status: subtask.status,
          isNextAction: subtask.isNextAction,
          energyRequired: subtask.energyRequired,
          completedAt: subtask.completedAt,
          elapsedSeconds: subtask.status == "done"
              ? _taskSubtaskDurationSeconds(subtask)
              : 0,
        ),
      )
      .toList();
}

int _taskSubtaskDurationSeconds(SubtaskResponse subtask) {
  final estimatedMinutes = subtask.estimatedMinutes;
  if (estimatedMinutes == null || estimatedMinutes <= 0) {
    return 60;
  }
  return estimatedMinutes * 60;
}

String? _firstIncompleteTaskSubtaskId(List<SubtaskResponse> subtasks) {
  final sortedSubtasks = [...subtasks]
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  for (final subtask in sortedSubtasks) {
    if (subtask.status != "done") {
      return subtask.id;
    }
  }
  return null;
}

String _questDifficultyFromTaskResponse(String? difficulty) {
  return switch (difficulty) {
    "low" || "easy" || "쉬움" => "쉬움",
    "high" || "hard" || "어려움" => "어려움",
    _ => "보통",
  };
}

int _taskDurationSecondsFromTaskResponse(
  TaskResponse task, {
  required String difficulty,
  required QuestItem fallbackDraft,
}) {
  final estimatedMinutes = task.estimatedMinutes;
  if (estimatedMinutes != null && estimatedMinutes > 0) {
    return estimatedMinutes * 60;
  }

  final metadataDuration =
      _metadataInt(task.metadata, "default_duration_seconds") ??
      _metadataInt(task.metadata, "defaultDurationSeconds") ??
      _nestedMetadataInt(
        task.metadata,
        "client_metadata",
        "default_duration_seconds",
      ) ??
      _nestedMetadataInt(
        task.metadata,
        "client_metadata",
        "defaultDurationSeconds",
      ) ??
      _nestedMetadataInt(
        task.metadata,
        "edited_fields",
        "default_duration_seconds",
      ) ??
      _nestedMetadataInt(
        task.metadata,
        "edited_fields",
        "defaultDurationSeconds",
      );
  if (metadataDuration != null && metadataDuration > 0) {
    return metadataDuration;
  }

  if (fallbackDraft.defaultDurationSeconds > 0) {
    return fallbackDraft.defaultDurationSeconds;
  }
  return defaultQuestDurationSecondsForDifficulty(difficulty);
}

String? _metadataString(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? _nestedMetadataString(
  Map<String, dynamic> metadata,
  String objectKey,
  String key,
) {
  final nested = metadata[objectKey];
  if (nested is Map) {
    final value = nested[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

int? _metadataInt(Map<String, dynamic> metadata, String key) {
  return _readInt(metadata[key]);
}

int? _nestedMetadataInt(
  Map<String, dynamic> metadata,
  String objectKey,
  String key,
) {
  final nested = metadata[objectKey];
  if (nested is Map) {
    return _readInt(nested[key]);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

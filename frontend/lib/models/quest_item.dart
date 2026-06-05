import 'package:start_on/models/quest_category.dart';
import 'package:start_on/models/quest_api_models.dart';

const _questItemNoChange = Object();
const questSyncTargetLocal = 'local';
const questSyncTargetQuest = 'quest';
const questSyncTargetTask = 'task';

class QuestItem {
  QuestItem({
    required this.id,
    required this.title,
    required this.exp,
    required this.difficulty,
    required this.category,
    required this.elapsedSeconds,
    required this.defaultDurationSeconds,
    this.dueDate,
    List<QuestSubtask>? subtasks,
    this.activeSubtaskId,
    this.aiSubtaskPrompt,
    String? syncTarget,
  }) : subtasks = List.unmodifiable(subtasks ?? const <QuestSubtask>[]),
       syncTarget = normalizeQuestSyncTarget(syncTarget);

  final String id;
  final String title;
  final int exp;
  final String difficulty;
  final String category;
  final int elapsedSeconds;
  final int defaultDurationSeconds;
  final DateTime? dueDate;
  final List<QuestSubtask> subtasks;
  final String? activeSubtaskId;
  final String? aiSubtaskPrompt;
  final String syncTarget;

  bool get syncsWithQuestApi => syncTarget == questSyncTargetQuest;
  bool get isTaskBacked => syncTarget == questSyncTargetTask;
  int get plannedSubtaskDurationSeconds {
    var total = 0;
    for (final subtask in subtasks) {
      total += subtask.plannedDurationSeconds;
    }
    return total;
  }

  int get effectiveDurationSeconds {
    if (subtasks.isNotEmpty && plannedSubtaskDurationSeconds > 0) {
      return plannedSubtaskDurationSeconds;
    }
    return defaultDurationSeconds;
  }

  String? get effectiveActiveSubtaskId {
    if (subtasks.isEmpty) {
      return null;
    }

    final activeSubtaskId = this.activeSubtaskId;
    if (activeSubtaskId != null) {
      for (final subtask in subtasks) {
        if (subtask.id == activeSubtaskId && !subtask.isDone) {
          return subtask.id;
        }
      }
    }

    for (final subtask in subtasks) {
      if (!subtask.isDone) {
        return subtask.id;
      }
    }
    return null;
  }

  QuestItem copyWith({
    String? id,
    String? title,
    int? exp,
    String? difficulty,
    String? category,
    int? elapsedSeconds,
    int? defaultDurationSeconds,
    Object? dueDate = _questItemNoChange,
    List<QuestSubtask>? subtasks,
    Object? activeSubtaskId = _questItemNoChange,
    Object? aiSubtaskPrompt = _questItemNoChange,
    String? syncTarget,
  }) {
    return QuestItem(
      id: id ?? this.id,
      title: title ?? this.title,
      exp: exp ?? this.exp,
      difficulty: difficulty ?? this.difficulty,
      category: category ?? this.category,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      defaultDurationSeconds:
          defaultDurationSeconds ?? this.defaultDurationSeconds,
      dueDate: identical(dueDate, _questItemNoChange)
          ? this.dueDate
          : dueDate as DateTime?,
      subtasks: subtasks ?? this.subtasks,
      activeSubtaskId: identical(activeSubtaskId, _questItemNoChange)
          ? this.activeSubtaskId
          : activeSubtaskId as String?,
      aiSubtaskPrompt: identical(aiSubtaskPrompt, _questItemNoChange)
          ? this.aiSubtaskPrompt
          : aiSubtaskPrompt as String?,
      syncTarget: syncTarget ?? this.syncTarget,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'exp': exp,
      'difficulty': difficulty,
      'category': category,
      'elapsedSeconds': elapsedSeconds,
      'defaultDurationSeconds': defaultDurationSeconds,
      'dueDate': dueDate?.toIso8601String(),
      'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
      'activeSubtaskId': activeSubtaskId,
      'aiSubtaskPrompt': aiSubtaskPrompt,
      'syncTarget': syncTarget,
    };
  }

  factory QuestItem.fromJson(Map<String, dynamic> json) {
    final difficulty = normalizeQuestDifficulty(json['difficulty'] as String?);
    final rawDueDate =
        (json['dueDate'] as String?) ?? (json['due_at'] as String?);
    return QuestItem(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '',
      exp: _readJsonInt(json['exp']) ?? 0,
      difficulty: difficulty,
      category: normalizeQuestCategory(json['category'] as String?),
      elapsedSeconds:
          _readJsonInt(json['elapsedSeconds']) ??
          _readJsonInt(json['elapsed_seconds']) ??
          0,
      defaultDurationSeconds:
          _readJsonInt(json['defaultDurationSeconds']) ??
          _readJsonInt(json['default_duration_seconds']) ??
          defaultQuestDurationSecondsForDifficulty(difficulty),
      dueDate: rawDueDate == null
          ? null
          : normalizeQuestDueDate(DateTime.tryParse(rawDueDate)),
      subtasks: _questSubtasksFromJson(json['subtasks']),
      activeSubtaskId:
          (json['activeSubtaskId'] as String?) ??
          (json['active_subtask_id'] as String?),
      aiSubtaskPrompt:
          (json['aiSubtaskPrompt'] as String?) ??
          (json['ai_subtask_prompt'] as String?),
      syncTarget: normalizeQuestSyncTarget(
        (json['syncTarget'] as String?) ?? (json['sync_target'] as String?),
      ),
    );
  }

  factory QuestItem.fromApiResponse(QuestItemResponse response) {
    return QuestItem(
      id: response.id,
      title: response.title,
      exp: response.exp,
      difficulty: questDifficultyFromApi(response.difficulty),
      category: normalizeQuestCategory(response.category),
      elapsedSeconds: response.elapsedSeconds,
      defaultDurationSeconds: response.defaultDurationSeconds,
      dueDate: normalizeQuestDueDate(response.dueAt),
      syncTarget: questSyncTargetQuest,
    );
  }

  QuestCreateRequest toCreateRequest() {
    return QuestCreateRequest(
      title: title,
      exp: exp,
      difficulty: questDifficultyToApi(difficulty),
      category: normalizeQuestCategory(category),
      defaultDurationSeconds: defaultDurationSeconds,
      dueAt: dueDate,
    );
  }

  QuestUpdateRequest toUpdateRequest() {
    return QuestUpdateRequest(
      title: title,
      exp: exp,
      difficulty: questDifficultyToApi(difficulty),
      category: normalizeQuestCategory(category),
      elapsedSeconds: elapsedSeconds,
      defaultDurationSeconds: defaultDurationSeconds,
      dueAt: dueDate,
    );
  }
}

class QuestSubtask {
  const QuestSubtask({
    required this.id,
    required this.title,
    required this.orderIndex,
    this.estimatedMinutes,
    this.status = 'todo',
    this.isNextAction = false,
    this.energyRequired,
    this.completedAt,
    this.elapsedSeconds = 0,
  });

  final String id;
  final String title;
  final int orderIndex;
  final int? estimatedMinutes;
  final String status;
  final bool isNextAction;
  final String? energyRequired;
  final DateTime? completedAt;
  final int elapsedSeconds;

  bool get isDone => status == 'done';
  int get plannedDurationSeconds {
    final minutes = estimatedMinutes;
    if (minutes == null || minutes <= 0) {
      return 60;
    }
    return minutes * 60;
  }

  int get clampedElapsedSeconds {
    if (elapsedSeconds < 0) {
      return 0;
    }
    if (elapsedSeconds > plannedDurationSeconds) {
      return plannedDurationSeconds;
    }
    return elapsedSeconds;
  }

  QuestSubtask copyWith({
    String? id,
    String? title,
    int? orderIndex,
    int? estimatedMinutes,
    String? status,
    bool? isNextAction,
    String? energyRequired,
    Object? completedAt = _questItemNoChange,
    int? elapsedSeconds,
  }) {
    return QuestSubtask(
      id: id ?? this.id,
      title: title ?? this.title,
      orderIndex: orderIndex ?? this.orderIndex,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      status: status ?? this.status,
      isNextAction: isNextAction ?? this.isNextAction,
      energyRequired: energyRequired ?? this.energyRequired,
      completedAt: identical(completedAt, _questItemNoChange)
          ? this.completedAt
          : completedAt as DateTime?,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'orderIndex': orderIndex,
      'estimatedMinutes': estimatedMinutes,
      'status': status,
      'isNextAction': isNextAction,
      'energyRequired': energyRequired,
      'completedAt': completedAt?.toIso8601String(),
      'elapsedSeconds': elapsedSeconds,
    };
  }

  factory QuestSubtask.fromJson(Map<String, dynamic> json) {
    final rawCompletedAt =
        (json['completedAt'] as String?) ?? (json['completed_at'] as String?);
    return QuestSubtask(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      orderIndex:
          _readJsonInt(json['orderIndex']) ??
          _readJsonInt(json['order_index']) ??
          0,
      estimatedMinutes:
          _readJsonInt(json['estimatedMinutes']) ??
          _readJsonInt(json['estimated_minutes']),
      status: json['status'] as String? ?? 'todo',
      isNextAction:
          json['isNextAction'] as bool? ??
          json['is_next_action'] as bool? ??
          false,
      energyRequired:
          (json['energyRequired'] as String?) ??
          (json['energy_required'] as String?),
      completedAt: rawCompletedAt == null
          ? null
          : DateTime.tryParse(rawCompletedAt),
      elapsedSeconds:
          _readJsonInt(json['elapsedSeconds']) ??
          _readJsonInt(json['elapsed_seconds']) ??
          0,
    );
  }
}

List<QuestSubtask> _questSubtasksFromJson(Object? value) {
  if (value is! List) {
    return const <QuestSubtask>[];
  }

  return value
      .whereType<Map>()
      .map((item) => QuestSubtask.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

int? _readJsonInt(Object? value) {
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

String normalizeQuestSyncTarget(String? value) {
  return switch (value) {
    questSyncTargetQuest => questSyncTargetQuest,
    questSyncTargetTask => questSyncTargetTask,
    _ => questSyncTargetLocal,
  };
}

int defaultQuestDurationSecondsForDifficulty(String difficulty) {
  return switch (normalizeQuestDifficulty(difficulty)) {
    '쉬움' => 25 * 60,
    '보통' => 45 * 60,
    _ => 90 * 60,
  };
}

String normalizeQuestDifficulty(String? difficulty) {
  return switch (difficulty) {
    '쉬움' || 'easy' => '쉬움',
    '보통' || 'normal' => '보통',
    '어려움' || 'hard' => '어려움',
    _ => '보통',
  };
}

String questDifficultyFromApi(String difficulty) {
  return normalizeQuestDifficulty(difficulty);
}

String questDifficultyToApi(String difficulty) {
  return switch (normalizeQuestDifficulty(difficulty)) {
    '쉬움' => 'easy',
    '보통' => 'normal',
    '어려움' => 'hard',
    _ => 'normal',
  };
}

DateTime? normalizeQuestDueDate(DateTime? value) {
  if (value == null) {
    return null;
  }

  final normalized = value.isUtc ? value.toLocal() : value;
  return DateTime(normalized.year, normalized.month, normalized.day);
}

String formatQuestDueDate(DateTime dueDate) {
  final normalized = normalizeQuestDueDate(dueDate)!;
  final year = normalized.year.toString().padLeft(4, '0');
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '$year.$month.$day';
}
